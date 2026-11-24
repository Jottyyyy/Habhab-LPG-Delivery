/** Database rows → the JSON the app reads. Dates are ISO strings, money is centavos. */
import { and, eq, inArray, sql } from "drizzle-orm";
import { customers, orderItems, orders, payments, products, users } from "../../db/schema.js";
import type { Db } from "./db.js";

type OrderRow = typeof orders.$inferSelect;
type ProductRow = typeof products.$inferSelect;
type PaymentRow = typeof payments.$inferSelect;
type CustomerRow = typeof customers.$inferSelect;

const iso = (d: Date | null | undefined) => (d ? d.toISOString() : null);

export function productJson(p: ProductRow) {
  return {
    id: p.id,
    name: p.name,
    kind: p.kind,
    description: p.description,
    price: p.price,
    stock: p.stock,
    active: p.active,
    sort: p.sort,
  };
}

export function paymentJson(p: PaymentRow, extra: { customerName?: string | null; orderRef?: string | null } = {}) {
  return {
    id: p.id,
    ref: p.ref,
    customerId: p.customerId,
    customerName: extra.customerName ?? null,
    orderId: p.orderId,
    orderRef: extra.orderRef ?? null,
    amount: p.amount,
    method: p.method,
    gcashRef: p.gcashRef,
    hasProof: Boolean(p.proofPath),
    status: p.status,
    note: p.note,
    rejectReason: p.rejectReason,
    createdAt: iso(p.createdAt),
    reviewedAt: iso(p.reviewedAt),
  };
}

export function customerJson(c: CustomerRow, balance: number) {
  return {
    id: c.id,
    name: c.name,
    phone: c.phone,
    address: c.address,
    landmark: c.landmark,
    lat: c.lat,
    lng: c.lng,
    notes: c.notes,
    hasApp: Boolean(c.userId),
    utangAllowed: c.utangAllowed,
    creditLimit: c.creditLimit,
    openingBalance: c.openingBalance,
    blocked: c.blocked,
    balance,
    createdAt: iso(c.createdAt),
  };
}

/**
 * Orders with their items, rider name and how much is paid.
 * `showRider`: include the rider's live location (only while on the way).
 */
export async function ordersJson(q: Db, rows: OrderRow[]) {
  if (rows.length === 0) return [];
  const ids = rows.map((r) => r.id);
  const items = await q.select().from(orderItems).where(inArray(orderItems.orderId, ids));
  const paid = await q
    .select({
      orderId: payments.orderId,
      confirmed: sql<number>`coalesce(sum(case when ${payments.status} = 'confirmed' then ${payments.amount} else 0 end), 0)::int`,
      pending: sql<number>`coalesce(sum(case when ${payments.status} = 'pending' then ${payments.amount} else 0 end), 0)::int`,
    })
    .from(payments)
    .where(inArray(payments.orderId, ids))
    .groupBy(payments.orderId);
  const riderIds = [...new Set(rows.map((r) => r.riderId).filter((x): x is string => Boolean(x)))];
  const riders = riderIds.length
    ? await q.select({ id: users.id, name: users.name, phone: users.phone }).from(users).where(inArray(users.id, riderIds))
    : [];

  return rows.map((o) => {
    const p = paid.find((x) => x.orderId === o.id);
    const rider = riders.find((r) => r.id === o.riderId);
    return {
      id: o.id,
      ref: o.ref,
      channel: o.channel,
      status: o.status,
      paymentMethod: o.paymentMethod,
      customerId: o.customerId,
      customerName: o.customerName,
      customerPhone: o.customerPhone,
      address: o.address,
      landmark: o.landmark,
      lat: o.lat,
      lng: o.lng,
      notes: o.notes,
      subtotal: o.subtotal,
      deliveryFee: o.deliveryFee,
      total: o.total,
      paid: Number(p?.confirmed ?? 0),
      pendingPaid: Number(p?.pending ?? 0),
      riderId: o.riderId,
      riderName: rider?.name ?? null,
      riderPhone: rider?.phone ?? null,
      rider:
        o.status === "on_the_way" && o.riderLat != null && o.riderLng != null
          ? { lat: o.riderLat, lng: o.riderLng, at: iso(o.riderLocAt) }
          : null,
      createdAt: iso(o.createdAt),
      updatedAt: iso(o.updatedAt),
      confirmedAt: iso(o.confirmedAt),
      outAt: iso(o.outAt),
      deliveredAt: iso(o.deliveredAt),
      cancelledAt: iso(o.cancelledAt),
      cancelReason: o.cancelReason,
      items: items
        .filter((i) => i.orderId === o.id)
        .map((i) => ({ productId: i.productId, name: i.name, unitPrice: i.unitPrice, qty: i.qty, lineTotal: i.lineTotal })),
    };
  });
}

export async function orderJson(q: Db, row: OrderRow) {
  const [one] = await ordersJson(q, [row]);
  return one;
}

/** Sum of payments for an order that still count (confirmed + pending). */
export async function orderPaidOrPending(q: Db, orderId: string): Promise<number> {
  const [r] = await q
    .select({ n: sql<number>`coalesce(sum(${payments.amount}), 0)::int` })
    .from(payments)
    .where(and(eq(payments.orderId, orderId), inArray(payments.status, ["confirmed", "pending"])));
  return Number(r?.n ?? 0);
}
