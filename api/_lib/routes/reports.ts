/**
 * Owner's report for a date range (Manila days): sales (app vs walk-in), quantity per product,
 * money collected by method, and utang still to collect.
 */
import { and, desc, eq, gte, lt, sql } from "drizzle-orm";
import { customers, orderItems, orders, payments } from "../../../db/schema.js";
import { requireOwner } from "../auth/guard.js";
import { requireSession } from "../auth/require-session.js";
import { db } from "../db.js";
import { ApiError, json } from "../http.js";
import { balanceSql } from "../ledger.js";

const DAY = /^\d{4}-\d{2}-\d{2}$/;

/** "2026-11-24" in Manila → the instant that day starts. */
export function manilaDayStart(day: string): Date {
  return new Date(`${day}T00:00:00+08:00`);
}

export async function report(req: Request): Promise<Response> {
  const s = await requireSession(req);
  requireOwner(s);
  const url = new URL(req.url);
  const from = url.searchParams.get("from") ?? "";
  const to = url.searchParams.get("to") ?? from;
  if (!DAY.test(from) || !DAY.test(to) || to < from) throw new ApiError(400, "Choose the dates again.");
  const start = manilaDayStart(from);
  const end = new Date(manilaDayStart(to).getTime() + 86_400_000);
  const d = db();
  const inRange = and(eq(orders.status, "delivered"), gte(orders.deliveredAt, start), lt(orders.deliveredAt, end));

  const byChannel = await d
    .select({
      channel: orders.channel,
      count: sql<number>`count(*)::int`,
      total: sql<number>`coalesce(sum(${orders.total}), 0)::int`,
      deliveryFees: sql<number>`coalesce(sum(${orders.deliveryFee}), 0)::int`,
    })
    .from(orders)
    .where(inRange)
    .groupBy(orders.channel);
  const byMethod = await d
    .select({ method: orders.paymentMethod, total: sql<number>`coalesce(sum(${orders.total}), 0)::int` })
    .from(orders)
    .where(inRange)
    .groupBy(orders.paymentMethod);
  const items = await d
    .select({
      name: orderItems.name,
      qty: sql<number>`sum(${orderItems.qty})::int`,
      total: sql<number>`sum(${orderItems.lineTotal})::int`,
    })
    .from(orderItems)
    .innerJoin(orders, eq(orders.id, orderItems.orderId))
    .where(inRange)
    .groupBy(orderItems.name)
    .orderBy(desc(sql`sum(${orderItems.qty})`));
  const collected = await d
    .select({ method: payments.method, total: sql<number>`coalesce(sum(${payments.amount}), 0)::int`, count: sql<number>`count(*)::int` })
    .from(payments)
    .where(and(eq(payments.status, "confirmed"), gte(payments.createdAt, start), lt(payments.createdAt, end)))
    .groupBy(payments.method);
  const owed = await d
    .select({ id: customers.id, name: customers.name, phone: customers.phone, balance: balanceSql })
    .from(customers)
    .where(eq(customers.active, true));
  const withUtang = owed.map((c) => ({ ...c, balance: Number(c.balance) })).filter((c) => c.balance > 0).sort((a, b) => b.balance - a.balance);

  const ch = (c: "app" | "walkin") => byChannel.find((r) => r.channel === c) ?? { count: 0, total: 0, deliveryFees: 0 };
  const sum = (rows: { total: number }[]) => rows.reduce((t, r) => t + Number(r.total), 0);
  return json({
    from,
    to,
    sales: {
      total: sum(byChannel),
      count: byChannel.reduce((t, r) => t + Number(r.count), 0),
      app: { count: Number(ch("app").count), total: Number(ch("app").total) },
      walkin: { count: Number(ch("walkin").count), total: Number(ch("walkin").total) },
      deliveryFees: byChannel.reduce((t, r) => t + Number(r.deliveryFees), 0),
      byMethod: Object.fromEntries(byMethod.map((r) => [r.method, Number(r.total)])),
    },
    items: items.map((i) => ({ name: i.name, qty: Number(i.qty), total: Number(i.total) })),
    collected: {
      total: sum(collected),
      cash: Number(collected.find((r) => r.method === "cash")?.total ?? 0),
      gcash: Number(collected.find((r) => r.method === "gcash")?.total ?? 0),
    },
    utang: { total: withUtang.reduce((t, c) => t + c.balance, 0), customers: withUtang.length, top: withUtang.slice(0, 10) },
  });
}
