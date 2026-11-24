/**
 * Customers and their listahan (store side).
 * Staff can look up customers, add walk-in suki and fix contact details.
 * Only the owner decides money things: utang on/off, credit limit, old balance, block, link, reset password.
 */
import { and, desc, eq, ilike, isNull, or } from "drizzle-orm";
import { z } from "zod";
import { customers, orders, payments, users } from "../../../db/schema.js";
import { hashPassword, temporaryPassword } from "../auth/crypto.js";
import { requireOwner, requireSeller } from "../auth/guard.js";
import { requireSession } from "../auth/require-session.js";
import { revokeAllSessions } from "../auth/sessions.js";
import { audit } from "../audit.js";
import { db, type Db } from "../db.js";
import { ApiError, json, readJson, uuidParam } from "../http.js";
import { balanceSql, customerBalance, customerLedger } from "../ledger.js";
import { formatPeso } from "../money.js";
import { normalizePhone } from "../phone.js";
import { customerJson, ordersJson } from "../views.js";
import { latField, lngField } from "./auth.js";

async function loadCustomer(q: Db, id: string) {
  const [c] = await q.select().from(customers).where(eq(customers.id, id)).limit(1);
  if (!c || !c.active) throw new ApiError(404, "That customer was not found.");
  return c;
}

const optionalPhone = z
  .string()
  .max(30)
  .nullable()
  .optional()
  .transform((v, ctx) => {
    if (v == null || v.trim() === "") return v === undefined ? undefined : null;
    const p = normalizePhone(v);
    if (!p) {
      ctx.addIssue({ code: "custom", message: "Enter a mobile number like 0917 123 4567." });
      return z.NEVER;
    }
    return p;
  });

const peso = z.number().int().min(0).max(100_000_000);

export async function listCustomers(req: Request): Promise<Response> {
  const s = await requireSession(req);
  requireSeller(s);
  const url = new URL(req.url);
  const q = (url.searchParams.get("q") ?? "").trim().slice(0, 60);
  const like = `%${q.replace(/[%_\\]/g, "")}%`;
  const rows = await db()
    .select({ c: customers, balance: balanceSql })
    .from(customers)
    .where(and(eq(customers.active, true), q ? or(ilike(customers.name, like), ilike(customers.phone, like), ilike(customers.address, like)) : undefined))
    .orderBy(customers.name)
    .limit(500);
  const list = rows.map((r) => customerJson(r.c, Number(r.balance)));
  return json({ customers: list, totalUtang: list.reduce((sum, c) => sum + Math.max(0, c.balance), 0) });
}

const NewCustomer = z.object({
  name: z.string().trim().min(2, "Enter the name.").max(80),
  phone: optionalPhone,
  address: z.string().trim().max(300).nullable().optional(),
  landmark: z.string().trim().max(200).nullable().optional(),
  notes: z.string().trim().max(300).nullable().optional(),
  lat: latField,
  lng: lngField,
  openingBalance: peso.optional(),
  utangAllowed: z.boolean().optional(),
  creditLimit: peso.nullable().optional(),
});

/** Add a walk-in suki (someone without the app). */
export async function addCustomer(req: Request): Promise<Response> {
  const s = await requireSession(req);
  requireSeller(s);
  const body = NewCustomer.parse(await readJson(req));
  const moneyFields = body.openingBalance !== undefined || body.utangAllowed !== undefined || body.creditLimit !== undefined;
  if (moneyFields && s.role !== "owner") throw new ApiError(403, "Only the owner can set utang or an old balance.");
  const d = db();
  const [c] = await d
    .insert(customers)
    .values({
      name: body.name,
      phone: body.phone ?? null,
      address: body.address || null,
      landmark: body.landmark || null,
      notes: body.notes || null,
      lat: body.lat ?? null,
      lng: body.lng ?? null,
      openingBalance: body.openingBalance ?? 0,
      // A suki the owner writes down by hand is usually already on the paper listahan.
      utangAllowed: body.utangAllowed ?? s.role === "owner",
      creditLimit: body.creditLimit ?? null,
      createdBy: s.userId,
      device: "Phone",
    })
    .returning();
  await audit(d, s.userId, "customer", c.id, "add", `${s.name} added customer ${c.name}${c.openingBalance ? ` (old balance ${formatPeso(c.openingBalance)})` : ""}`);
  return json({ customer: customerJson(c, c.openingBalance) }, { status: 201 });
}

/** Profile + listahan + recent orders. */
export async function getCustomer(req: Request, params: Record<string, string>): Promise<Response> {
  const s = await requireSession(req);
  requireSeller(s);
  const d = db();
  const c = await loadCustomer(d, uuidParam(params, "id", "That customer"));
  const ledger = await customerLedger(d, c.id);
  const recent = await d.select().from(orders).where(eq(orders.customerId, c.id)).orderBy(desc(orders.createdAt)).limit(30);
  // Walk-in records with the same number that could be linked to this app account.
  const linkable =
    c.userId && c.phone
      ? await d
          .select({ id: customers.id, name: customers.name })
          .from(customers)
          .where(and(eq(customers.phone, c.phone), isNull(customers.userId), eq(customers.active, true)))
      : [];
  return json({ customer: customerJson(c, ledger.balance), ledger: ledger.entries, orders: await ordersJson(d, recent), linkable });
}

const PatchCustomer = NewCustomer.partial().extend({ blocked: z.boolean().optional() });

export async function updateCustomer(req: Request, params: Record<string, string>): Promise<Response> {
  const s = await requireSession(req);
  requireSeller(s);
  const body = PatchCustomer.parse(await readJson(req));
  const ownerOnly = ["openingBalance", "utangAllowed", "creditLimit", "blocked"] as const;
  if (ownerOnly.some((k) => body[k] !== undefined) && s.role !== "owner") throw new ApiError(403, "Only the owner can change utang settings.");
  const d = db();
  const c = await loadCustomer(d, uuidParam(params, "id", "That customer"));
  const now = new Date();
  const [u] = await d
    .update(customers)
    .set({
      ...(body.name !== undefined && { name: body.name }),
      ...(body.phone !== undefined && { phone: body.phone }),
      ...(body.address !== undefined && { address: body.address || null }),
      ...(body.landmark !== undefined && { landmark: body.landmark || null }),
      ...(body.notes !== undefined && { notes: body.notes || null }),
      ...(body.lat !== undefined && { lat: body.lat }),
      ...(body.lng !== undefined && { lng: body.lng }),
      ...(body.openingBalance !== undefined && { openingBalance: body.openingBalance }),
      ...(body.utangAllowed !== undefined && { utangAllowed: body.utangAllowed }),
      ...(body.creditLimit !== undefined && { creditLimit: body.creditLimit }),
      ...(body.blocked !== undefined && { blocked: body.blocked }),
      updatedAt: now,
    })
    .where(eq(customers.id, c.id))
    .returning();
  await audit(d, s.userId, "customer", c.id, "update", `${s.name} updated customer ${u.name}`, {
    before: { utangAllowed: c.utangAllowed, creditLimit: c.creditLimit, openingBalance: c.openingBalance, blocked: c.blocked },
    after: { utangAllowed: u.utangAllowed, creditLimit: u.creditLimit, openingBalance: u.openingBalance, blocked: u.blocked },
  });
  return json({ customer: customerJson(u, await customerBalance(d, u.id)) });
}

const LinkBody = z.object({ walkinId: z.uuid() });

/**
 * A walk-in suki later made an app account: move the old record's orders, payments and old
 * balance onto the app account. Owner only (there is no SMS check of the number).
 */
export async function linkCustomer(req: Request, params: Record<string, string>): Promise<Response> {
  const s = await requireSession(req);
  requireOwner(s);
  const { walkinId } = LinkBody.parse(await readJson(req));
  const appId = uuidParam(params, "id", "That customer");
  const merged = await db().transaction(async (tx) => {
    const app = await loadCustomer(tx, appId);
    const walkin = await loadCustomer(tx, walkinId);
    if (!app.userId) throw new ApiError(400, "Open the customer who has the app, then link the old record.");
    if (walkin.userId) throw new ApiError(400, "Only a record without the app can be linked.");
    if (walkin.id === app.id) throw new ApiError(400, "That is the same record.");
    const now = new Date();
    await tx.update(orders).set({ customerId: app.id, updatedAt: now }).where(eq(orders.customerId, walkin.id));
    await tx.update(payments).set({ customerId: app.id, updatedAt: now }).where(eq(payments.customerId, walkin.id));
    const [u] = await tx
      .update(customers)
      .set({
        openingBalance: app.openingBalance + walkin.openingBalance,
        utangAllowed: app.utangAllowed || walkin.utangAllowed,
        creditLimit: app.creditLimit ?? walkin.creditLimit,
        notes: [app.notes, walkin.notes].filter(Boolean).join("\n") || null,
        updatedAt: now,
      })
      .where(eq(customers.id, app.id))
      .returning();
    await tx.update(customers).set({ active: false, mergedInto: app.id, updatedAt: now }).where(eq(customers.id, walkin.id));
    await audit(tx, s.userId, "customer", app.id, "link", `${s.name} linked the old record of ${walkin.name} to the app account of ${app.name}`);
    return u;
  });
  return json({ customer: customerJson(merged, await customerBalance(db(), merged.id)) });
}

/** Customer forgot the password: the owner gives a temporary one (they must change it after signing in). */
export async function resetCustomerPassword(req: Request, params: Record<string, string>): Promise<Response> {
  const s = await requireSession(req);
  requireOwner(s);
  const d = db();
  const c = await loadCustomer(d, uuidParam(params, "id", "That customer"));
  if (!c.userId) throw new ApiError(400, "This customer has no app account.");
  const password = temporaryPassword();
  await d
    .update(users)
    .set({ passwordHash: await hashPassword(password), mustChangePassword: true, active: true, updatedAt: new Date() })
    .where(eq(users.id, c.userId));
  await revokeAllSessions(c.userId);
  await audit(d, s.userId, "user", c.userId, "reset_password", `${s.name} gave ${c.name} a temporary password`);
  return json({ temporaryPassword: password, phone: c.phone });
}
