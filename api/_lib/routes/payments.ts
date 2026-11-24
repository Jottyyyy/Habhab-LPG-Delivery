/**
 * Payments.
 * - Customer: "I sent GCash" (amount + reference no.), then attaches the screenshot.
 * - Store: records cash (paying utang), checks GCash (confirm / reject), sees the screenshot.
 * Screenshots live in the PRIVATE Blob store and are only streamed through the API.
 */
import { randomUUID } from "node:crypto";
import { and, desc, eq, inArray } from "drizzle-orm";
import { z } from "zod";
import { customers, orders, payments } from "../../../db/schema.js";
import { nextRef } from "../../../db/refs.js";
import { requireCustomer, requireOwner, requireSeller } from "../auth/guard.js";
import { requireSession } from "../auth/require-session.js";
import { audit } from "../audit.js";
import { db } from "../db.js";
import { ApiError, json, readJson, uuidParam } from "../http.js";
import { customerBalance } from "../ledger.js";
import { formatPeso } from "../money.js";
import { storage } from "../storage.js";
import { paymentJson } from "../views.js";
import { myCustomer } from "./orders.js";

export const MAX_PHOTO_BYTES = 4_000_000;
const amountField = z.number().int().min(100, "Enter the amount.").max(10_000_000);

/** JPEG or PNG by the first bytes (never trust the file name). */
export function imageKind(bytes: Uint8Array): "jpeg" | "png" | null {
  if (bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) return "jpeg";
  if (bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47) return "png";
  return null;
}

/** Read a raw JPEG/PNG request body (max 4 MB). */
export async function readImage(req: Request): Promise<{ bytes: Uint8Array; kind: "jpeg" | "png" }> {
  const length = Number(req.headers.get("content-length") ?? 0);
  if (length > MAX_PHOTO_BYTES) throw new ApiError(413, "The photo is too large. Choose a smaller one.");
  const bytes = new Uint8Array(await req.arrayBuffer());
  if (bytes.length === 0) throw new ApiError(400, "The photo is empty.");
  if (bytes.length > MAX_PHOTO_BYTES) throw new ApiError(413, "The photo is too large. Choose a smaller one.");
  const kind = imageKind(bytes);
  if (!kind) throw new ApiError(415, "Only photos (JPEG or PNG) can be attached.");
  return { bytes, kind };
}

// ---------------------------------------------------------------- customer

const GcashBody = z.object({
  amount: amountField,
  gcashRef: z.string().trim().min(4, "Enter the GCash reference number.").max(40),
  orderId: z.uuid().nullable().optional(),
});

export async function sendGcash(req: Request): Promise<Response> {
  const s = await requireSession(req);
  requireCustomer(s);
  const body = GcashBody.parse(await readJson(req));
  const p = await db().transaction(async (tx) => {
    const c = await myCustomer(tx, s.userId);
    let orderRef: string | null = null;
    if (body.orderId) {
      const [o] = await tx.select().from(orders).where(eq(orders.id, body.orderId)).limit(1);
      if (!o || o.customerId !== c.id) throw new ApiError(404, "That order was not found.");
      if (o.status === "cancelled") throw new ApiError(409, "That order is cancelled.");
      orderRef = o.ref;
    }
    const [row] = await tx
      .insert(payments)
      .values({
        ref: await nextRef(tx, "P"),
        customerId: c.id,
        orderId: body.orderId ?? null,
        amount: body.amount,
        method: "gcash",
        gcashRef: body.gcashRef,
        status: "pending",
        note: orderRef ? `GCash for ${orderRef}` : "GCash for utang",
        createdBy: s.userId,
        device: "Phone",
      })
      .returning();
    await audit(tx, s.userId, "payment", row.id, "gcash", `${c.name} sent GCash ${formatPeso(body.amount)} (ref ${body.gcashRef})`);
    return row;
  });
  return json({ payment: paymentJson(p) }, { status: 201 });
}

export async function myPayments(req: Request): Promise<Response> {
  const s = await requireSession(req);
  requireCustomer(s);
  const d = db();
  const c = await myCustomer(d, s.userId);
  const rows = await d.select().from(payments).where(eq(payments.customerId, c.id)).orderBy(desc(payments.createdAt)).limit(50);
  return json({ payments: rows.map((p) => paymentJson(p)) });
}

/** POST /api/uploads/proof?paymentId=…  (body: the compressed JPEG/PNG) */
export async function uploadProof(req: Request): Promise<Response> {
  const s = await requireSession(req);
  const paymentId = uuidParam({ id: new URL(req.url).searchParams.get("paymentId") ?? "" }, "id", "That payment");
  const d = db();
  const [p] = await d.select().from(payments).where(eq(payments.id, paymentId)).limit(1);
  if (!p) throw new ApiError(404, "That payment was not found.");
  if (s.role === "customer") {
    const c = await myCustomer(d, s.userId);
    if (p.customerId !== c.id) throw new ApiError(404, "That payment was not found.");
    if (p.status !== "pending") throw new ApiError(409, "This payment was already checked by the store.");
  }
  const { bytes, kind } = await readImage(req);
  const blob = await storage().put(`proofs/${paymentId}/${randomUUID()}.${kind === "png" ? "png" : "jpg"}`, Buffer.from(bytes), `image/${kind}`);
  const [row] = await d
    .update(payments)
    .set({ proofPath: blob.pathname, proofSize: bytes.length, updatedAt: new Date() })
    .where(eq(payments.id, paymentId))
    .returning();
  return json({ payment: paymentJson(row) });
}

/** The screenshot: the store, or the customer who sent it. */
export async function viewProof(req: Request, params: Record<string, string>): Promise<Response> {
  const s = await requireSession(req);
  const id = uuidParam(params, "id", "That photo");
  const d = db();
  const [p] = await d.select().from(payments).where(eq(payments.id, id)).limit(1);
  if (!p?.proofPath) throw new ApiError(404, "No photo.");
  if (s.role === "customer") {
    const c = await myCustomer(d, s.userId);
    if (p.customerId !== c.id) throw new ApiError(404, "No photo.");
  }
  const file = await storage().get(p.proofPath);
  if (!file) throw new ApiError(404, "No photo.");
  return new Response(file.stream, {
    headers: { "Content-Type": file.contentType ?? "image/jpeg", "Cache-Control": "private, no-store", "X-Content-Type-Options": "nosniff" },
  });
}

// ---------------------------------------------------------------- store

const CashBody = z.object({
  customerId: z.uuid(),
  amount: amountField,
  method: z.enum(["cash", "gcash"]).default("cash"),
  gcashRef: z.string().trim().max(40).nullable().optional(),
  note: z.string().trim().max(200).nullable().optional(),
});

/** The customer paid (part of) their utang at the store or to the rider. Counts at once. */
export async function recordPayment(req: Request): Promise<Response> {
  const s = await requireSession(req);
  requireSeller(s);
  const body = CashBody.parse(await readJson(req));
  const result = await db().transaction(async (tx) => {
    const [c] = await tx.select().from(customers).where(eq(customers.id, body.customerId)).limit(1);
    if (!c || !c.active) throw new ApiError(404, "That customer was not found.");
    const now = new Date();
    const [row] = await tx
      .insert(payments)
      .values({
        ref: await nextRef(tx, "P"),
        customerId: c.id,
        amount: body.amount,
        method: body.method,
        gcashRef: body.gcashRef || null,
        status: "confirmed",
        note: body.note || "Paid utang",
        reviewedBy: s.userId,
        reviewedAt: now,
        createdBy: s.userId,
        device: "Phone",
      })
      .returning();
    await audit(tx, s.userId, "payment", row.id, "record", `${s.name} received ${formatPeso(body.amount)} ${body.method} from ${c.name}`);
    return { row, balance: await customerBalance(tx, c.id), name: c.name };
  });
  return json({ payment: paymentJson(result.row, { customerName: result.name }), balance: result.balance }, { status: 201 });
}

/** GCash waiting to be checked (and the latest checked ones). */
export async function listPayments(req: Request): Promise<Response> {
  const s = await requireSession(req);
  requireSeller(s);
  const status = new URL(req.url).searchParams.get("status");
  const d = db();
  const rows = await d
    .select({ p: payments, customerName: customers.name, orderRef: orders.ref })
    .from(payments)
    .leftJoin(customers, eq(customers.id, payments.customerId))
    .leftJoin(orders, eq(orders.id, payments.orderId))
    .where(status === "pending" ? eq(payments.status, "pending") : inArray(payments.status, ["pending", "confirmed", "rejected"]))
    .orderBy(desc(payments.createdAt))
    .limit(status === "pending" ? 200 : 60);
  return json({ payments: rows.map((r) => paymentJson(r.p, { customerName: r.customerName, orderRef: r.orderRef })) });
}

const ReviewBody = z.object({ reason: z.string().trim().max(200).optional() });

async function review(req: Request, params: Record<string, string>, to: "confirmed" | "rejected"): Promise<Response> {
  const s = await requireSession(req);
  requireSeller(s);
  const id = uuidParam(params, "id", "That payment");
  const { reason } = ReviewBody.parse(await readJson(req).catch(() => ({})));
  if (to === "rejected" && !reason) throw new ApiError(400, "Write why the GCash payment is rejected (e.g. not received).");
  const d = db();
  const row = await d.transaction(async (tx) => {
    const [p] = await tx.select().from(payments).where(eq(payments.id, id)).limit(1);
    if (!p) throw new ApiError(404, "That payment was not found.");
    if (p.status !== "pending") {
      // Changing a checked payment is an owner-only correction.
      requireOwner(s);
    }
    const now = new Date();
    const [u] = await tx
      .update(payments)
      .set({ status: to, rejectReason: to === "rejected" ? reason : null, reviewedBy: s.userId, reviewedAt: now, updatedAt: now })
      .where(and(eq(payments.id, id)))
      .returning();
    await audit(tx, s.userId, "payment", id, to, `${s.name} ${to === "confirmed" ? "confirmed" : "rejected"} ${p.ref} (${formatPeso(p.amount)})${reason ? `: ${reason}` : ""}`);
    return u;
  });
  return json({ payment: paymentJson(row) });
}

export const confirmPayment = (req: Request, params: Record<string, string>) => review(req, params, "confirmed");
export const rejectPayment = (req: Request, params: Record<string, string>) => review(req, params, "rejected");
