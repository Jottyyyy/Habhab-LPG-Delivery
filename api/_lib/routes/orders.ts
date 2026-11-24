/**
 * Gasul orders from the app.
 *   pending → confirmed → on_the_way → delivered        (or cancelled, with a reason)
 * Customers place, see and cancel (while pending) their own orders.
 * The store (owner/staff) confirms, starts the delivery (shares the rider's GPS), and marks it delivered.
 */
import { and, desc, eq, gte, inArray, or } from "drizzle-orm";
import { z } from "zod";
import { customers, orders, payments, users } from "../../../db/schema.js";
import { nextRef } from "../../../db/refs.js";
import { requireCustomer, requireOwner, requireSeller } from "../auth/guard.js";
import { requireSession, type SessionCtx } from "../auth/require-session.js";
import { audit } from "../audit.js";
import { CartItems, insertLines, moveStock, priceCart } from "../cart.js";
import { db, type Db } from "../db.js";
import { ApiError, json, readJson, uuidParam } from "../http.js";
import { customerBalance } from "../ledger.js";
import { formatPeso } from "../money.js";
import { getSettings } from "../store-settings.js";
import { orderJson, orderPaidOrPending, ordersJson } from "../views.js";
import { latField, lngField } from "./auth.js";

type OrderRow = typeof orders.$inferSelect;

/** The customer record behind a customer account. */
export async function myCustomer(q: Db, userId: string) {
  const [c] = await q.select().from(customers).where(eq(customers.userId, userId)).limit(1);
  if (!c) throw new ApiError(404, "Your profile was not found. Please sign in again.");
  return c;
}

async function loadOrder(q: Db, id: string): Promise<OrderRow> {
  const [o] = await q.select().from(orders).where(eq(orders.id, id)).limit(1);
  if (!o) throw new ApiError(404, "That order was not found.");
  return o;
}

/** Customers may only touch their own orders. */
async function loadOrderFor(q: Db, s: SessionCtx, id: string): Promise<OrderRow> {
  const o = await loadOrder(q, id);
  if (s.role === "customer") {
    const c = await myCustomer(q, s.userId);
    if (o.customerId !== c.id) throw new ApiError(404, "That order was not found.");
  }
  return o;
}

// ---------------------------------------------------------------- customer: place an order

const PlaceBody = z.object({
  items: CartItems,
  paymentMethod: z.enum(["cash", "gcash", "utang"]),
  address: z.string().trim().min(5, "Enter the delivery address.").max(300).optional(),
  landmark: z.string().trim().max(200).nullable().optional(),
  lat: latField,
  lng: lngField,
  notes: z.string().trim().max(300).nullable().optional(),
});

export async function placeOrder(req: Request): Promise<Response> {
  const s = await requireSession(req);
  requireCustomer(s);
  const body = PlaceBody.parse(await readJson(req));

  const created = await db().transaction(async (tx) => {
    const st = await getSettings(tx);
    if (!st.isOpen) throw new ApiError(409, st.closedMessage || "The store is closed right now. Please order again later.", { code: "store_closed" });
    const c = await myCustomer(tx, s.userId);
    if (c.blocked) throw new ApiError(403, "Your account cannot order right now. Please call the store.");
    const address = body.address ?? c.address;
    if (!address) throw new ApiError(400, "Enter the delivery address.");

    const { lines, subtotal } = await priceCart(tx, body.items);
    const total = subtotal + st.deliveryFee;

    if (body.paymentMethod === "utang") {
      if (!c.utangAllowed) throw new ApiError(403, "Utang is not turned on for your account. Please ask the store.", { code: "utang_not_allowed" });
      if (c.creditLimit != null) {
        const balance = await customerBalance(tx, c.id);
        if (balance + total > c.creditLimit) {
          throw new ApiError(409, `This order is over your utang limit (${formatPeso(c.creditLimit)}). Your balance now is ${formatPeso(balance)}.`, {
            code: "over_limit",
          });
        }
      }
    }

    const ref = await nextRef(tx, "O");
    const [o] = await tx
      .insert(orders)
      .values({
        ref,
        channel: "app",
        customerId: c.id,
        customerName: c.name,
        customerPhone: c.phone,
        status: "pending",
        paymentMethod: body.paymentMethod,
        address,
        landmark: body.address ? (body.landmark ?? null) : c.landmark,
        lat: body.address ? (body.lat ?? null) : c.lat,
        lng: body.address ? (body.lng ?? null) : c.lng,
        notes: body.notes || null,
        subtotal,
        deliveryFee: st.deliveryFee,
        total,
        createdBy: s.userId,
        device: "Phone",
      })
      .returning();
    await insertLines(tx, o.id, s.userId, lines);
    await audit(tx, s.userId, "order", o.id, "place", `${c.name} ordered ${ref} (${formatPeso(total)}, ${body.paymentMethod})`);
    return o;
  });
  return json({ order: await orderJson(db(), created) }, { status: 201 });
}

// ---------------------------------------------------------------- read

export async function myOrders(req: Request): Promise<Response> {
  const s = await requireSession(req);
  requireCustomer(s);
  const d = db();
  const c = await myCustomer(d, s.userId);
  const rows = await d.select().from(orders).where(eq(orders.customerId, c.id)).orderBy(desc(orders.createdAt)).limit(50);
  return json({ orders: await ordersJson(d, rows) });
}

export async function getOrder(req: Request, params: Record<string, string>): Promise<Response> {
  const s = await requireSession(req);
  const d = db();
  const o = await loadOrderFor(d, s, uuidParam(params, "id", "That order"));
  return json({ order: await orderJson(d, o), serverTime: new Date().toISOString() });
}

/** Seller's board: open orders, recently finished ones, and counts for badges. Polled every ~15s. */
export async function sellerOrders(req: Request): Promise<Response> {
  const s = await requireSession(req);
  requireSeller(s);
  const d = db();
  const now = new Date();
  const active = await d
    .select()
    .from(orders)
    .where(and(eq(orders.channel, "app"), inArray(orders.status, ["pending", "confirmed", "on_the_way"])))
    .orderBy(orders.createdAt);
  const since = new Date(now.getTime() - 36 * 3600_000);
  const done = await d
    .select()
    .from(orders)
    .where(
      and(
        eq(orders.channel, "app"),
        or(and(eq(orders.status, "delivered"), gte(orders.deliveredAt, since)), and(eq(orders.status, "cancelled"), gte(orders.cancelledAt, since))),
      ),
    )
    .orderBy(desc(orders.updatedAt))
    .limit(40);
  const pendingPayments = await d.select({ id: payments.id }).from(payments).where(eq(payments.status, "pending"));
  const riders = await d
    .select({ id: users.id, name: users.name, role: users.role })
    .from(users)
    .where(and(eq(users.active, true), inArray(users.role, ["owner", "staff"])))
    .orderBy(users.name);
  return json({
    active: await ordersJson(d, active),
    done: await ordersJson(d, done),
    counts: {
      pending: active.filter((o) => o.status === "pending").length,
      gcashToCheck: pendingPayments.length,
    },
    riders,
    serverTime: now.toISOString(),
  });
}

// ---------------------------------------------------------------- status changes (store)

async function setStatus(s: SessionCtx, id: string, allowedFrom: OrderRow["status"][], patch: Partial<typeof orders.$inferInsert>, summary: (o: OrderRow) => string) {
  return db().transaction(async (tx) => {
    const o = await loadOrder(tx, id);
    if (!allowedFrom.includes(o.status)) throw new ApiError(409, `This order is already ${o.status.replace(/_/g, " ")}.`, { code: "wrong_status" });
    const [u] = await tx
      .update(orders)
      .set({ ...patch, updatedAt: new Date() })
      .where(eq(orders.id, id))
      .returning();
    await audit(tx, s.userId, "order", id, String(patch.status ?? "update"), summary(o));
    return u;
  });
}

export async function confirmOrder(req: Request, params: Record<string, string>): Promise<Response> {
  const s = await requireSession(req);
  requireSeller(s);
  const id = uuidParam(params, "id", "That order");
  const o = await setStatus(s, id, ["pending"], { status: "confirmed", confirmedAt: new Date() }, (o) => `${s.name} confirmed ${o.ref}`);
  return json({ order: await orderJson(db(), o) });
}

const AssignBody = z.object({ riderId: z.uuid().nullable() });

export async function assignRider(req: Request, params: Record<string, string>): Promise<Response> {
  const s = await requireSession(req);
  requireOwner(s);
  const id = uuidParam(params, "id", "That order");
  const { riderId } = AssignBody.parse(await readJson(req));
  const d = db();
  if (riderId) {
    const [r] = await d.select().from(users).where(eq(users.id, riderId)).limit(1);
    if (!r || !r.active || r.role === "customer") throw new ApiError(400, "Choose a store account as the rider.");
  }
  const o = await setStatus(s, id, ["pending", "confirmed", "on_the_way"], { riderId }, (o) => `${s.name} set the rider of ${o.ref}`);
  return json({ order: await orderJson(d, o) });
}

/** "On the way": whoever starts it becomes the rider (unless the owner already chose one). */
export async function startDelivery(req: Request, params: Record<string, string>): Promise<Response> {
  const s = await requireSession(req);
  requireSeller(s);
  const id = uuidParam(params, "id", "That order");
  const d = db();
  const current = await loadOrder(d, id);
  const now = new Date();
  const o = await setStatus(
    s,
    id,
    ["pending", "confirmed"],
    { status: "on_the_way", riderId: current.riderId ?? s.userId, outAt: now, confirmedAt: current.confirmedAt ?? now },
    (o) => `${s.name} started delivering ${o.ref}`,
  );
  return json({ order: await orderJson(d, o) });
}

const LocationBody = z.object({ lat: z.number().min(-90).max(90), lng: z.number().min(-180).max(180) });

/** The rider's phone sends its GPS every ~15s while the delivery screen is open. */
export async function riderLocation(req: Request, params: Record<string, string>): Promise<Response> {
  const s = await requireSession(req);
  requireSeller(s);
  const id = uuidParam(params, "id", "That order");
  const body = LocationBody.parse(await readJson(req));
  const d = db();
  const o = await loadOrder(d, id);
  if (o.status !== "on_the_way") return json({ ok: false, status: o.status });
  if (o.riderId && o.riderId !== s.userId && s.role !== "owner") throw new ApiError(403, "Another rider has this delivery.");
  // Not counted as an "update" (updatedAt stays), so it doesn't wake up the seller's board.
  await d.update(orders).set({ riderLat: body.lat, riderLng: body.lng, riderLocAt: new Date() }).where(eq(orders.id, id));
  return json({ ok: true, status: o.status });
}

const DeliverBody = z.object({ paid: z.enum(["cash", "gcash", "utang"]) });

/**
 * Delivered. `paid` says how the customer settled it:
 * - cash: the rider got cash → a confirmed cash payment for what is still unpaid.
 * - gcash: paid by GCash → if the customer already sent one, it waits in "GCash to check";
 *          if not, the store confirms it received it (a confirmed GCash payment).
 * - utang: not paid → it goes on the listahan.
 */
export async function deliverOrder(req: Request, params: Record<string, string>): Promise<Response> {
  const s = await requireSession(req);
  requireSeller(s);
  const id = uuidParam(params, "id", "That order");
  const { paid } = DeliverBody.parse(await readJson(req));
  const updated = await db().transaction(async (tx) => {
    const o = await loadOrder(tx, id);
    if (!["pending", "confirmed", "on_the_way"].includes(o.status)) {
      throw new ApiError(409, `This order is already ${o.status.replace(/_/g, " ")}.`, { code: "wrong_status" });
    }
    const now = new Date();
    const [u] = await tx
      .update(orders)
      .set({
        status: "delivered",
        deliveredAt: now,
        confirmedAt: o.confirmedAt ?? now,
        riderId: o.riderId ?? s.userId,
        paymentMethod: paid,
        updatedAt: now,
      })
      .where(eq(orders.id, id))
      .returning();
    await moveStock(tx, id, -1);
    const covered = await orderPaidOrPending(tx, id);
    const due = o.total - covered;
    if (due > 0 && paid !== "utang") {
      await tx.insert(payments).values({
        ref: await nextRef(tx, "P"),
        customerId: o.customerId,
        orderId: o.id,
        amount: due,
        method: paid,
        status: "confirmed",
        note: `Paid on delivery of ${o.ref}`,
        reviewedBy: s.userId,
        reviewedAt: now,
        // Same moment as the delivery, so the listahan lists the order first, then the payment.
        createdAt: now,
        createdBy: s.userId,
        device: "Phone",
      });
    }
    await audit(tx, s.userId, "order", id, "delivered", `${s.name} delivered ${o.ref} (${paid === "utang" ? "utang" : `paid ${paid}`})`);
    return u;
  });
  return json({ order: await orderJson(db(), updated) });
}

const CancelBody = z.object({ reason: z.string().trim().max(200).optional() });

/**
 * Cancel. Customers: own order, only while pending. Store: any open order, with a reason.
 * Owner: may also void a delivered order (stock goes back, payments taken for it are rejected).
 */
export async function cancelOrder(req: Request, params: Record<string, string>): Promise<Response> {
  const s = await requireSession(req);
  const id = uuidParam(params, "id", "That order");
  const { reason } = CancelBody.parse(await readJson(req).catch(() => ({})));
  const updated = await db().transaction(async (tx) => {
    const o = await loadOrderFor(tx, s, id);
    if (o.status === "cancelled") throw new ApiError(409, "This order is already cancelled.", { code: "wrong_status" });
    if (s.role === "customer" && o.status !== "pending") {
      throw new ApiError(409, "The store already accepted this order. Please call the store to cancel it.", { code: "wrong_status" });
    }
    if (s.role !== "customer" && !reason) throw new ApiError(400, "Write the reason for cancelling.");
    const wasDelivered = o.status === "delivered";
    if (wasDelivered && s.role !== "owner") throw new ApiError(403, "Only the owner can cancel a finished sale.");
    const now = new Date();
    const [u] = await tx
      .update(orders)
      .set({ status: "cancelled", cancelledAt: now, cancelledBy: s.userId, cancelReason: reason || "Cancelled by customer", updatedAt: now })
      .where(eq(orders.id, id))
      .returning();
    if (wasDelivered) await moveStock(tx, id, 1);
    // Payments the store wrote down for this sale (cash on delivery, POS) and GCash not yet
    // checked no longer count. GCash the customer sent and the store already confirmed stays
    // as credit on their listahan (the store owes it back or uses it for the next order).
    const [owner] = o.customerId
      ? await tx.select({ userId: customers.userId }).from(customers).where(eq(customers.id, o.customerId)).limit(1)
      : [];
    const linked = await tx
      .select({ id: payments.id, status: payments.status, createdBy: payments.createdBy })
      .from(payments)
      .where(and(eq(payments.orderId, id), inArray(payments.status, ["pending", "confirmed"])));
    const drop = linked.filter((p) => p.status === "pending" || !owner?.userId || p.createdBy !== owner.userId).map((p) => p.id);
    if (drop.length) {
      await tx
        .update(payments)
        .set({ status: "rejected", rejectReason: `Order ${o.ref} cancelled`, reviewedBy: s.userId, reviewedAt: now, updatedAt: now })
        .where(inArray(payments.id, drop));
    }
    await audit(tx, s.userId, "order", id, "cancel", `${s.name} cancelled ${o.ref}${reason ? `: ${reason}` : ""}`);
    return u;
  });
  return json({ order: await orderJson(db(), updated) });
}
