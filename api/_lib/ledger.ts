/**
 * Utang (listahan) math — ONE formula used everywhere:
 *   balance = opening_balance + Σ total of DELIVERED orders − Σ CONFIRMED payments
 * Pending GCash payments are shown but do not lower the balance until the seller confirms them.
 */
import { and, desc, eq, inArray, sql } from "drizzle-orm";
import { customers, orders, payments } from "../../db/schema.js";
import type { Db } from "./db.js";

/**
 * SQL for the balance of the customer row in scope (use inside a select FROM "customers",
 * without an alias). Column names are written out in full on purpose: Drizzle may print a
 * column without its table name, and inside the subqueries a bare "id" would mean the
 * order's / payment's own id.
 */
export const balanceSql = sql<number>`(
  "customers"."opening_balance"
  + coalesce((select sum(o.total) from orders o where o.customer_id = "customers"."id" and o.status = 'delivered'), 0)
  - coalesce((select sum(p.amount) from payments p where p.customer_id = "customers"."id" and p.status = 'confirmed'), 0)
)::int`;

export async function customerBalance(q: Db, customerId: string): Promise<number> {
  const [row] = await q.select({ balance: balanceSql }).from(customers).where(eq(customers.id, customerId)).limit(1);
  return Number(row?.balance ?? 0);
}

export type LedgerEntry = {
  kind: "opening" | "order" | "payment";
  id: string | null;
  ref: string | null;
  at: string;
  label: string;
  /** + adds to utang, − lowers it. 0 for entries that don't count (pending/rejected). */
  amount: number;
  status: string | null;
  /** Running balance after this entry (counted entries only). */
  balance: number;
};

/**
 * The customer's listahan: delivered orders (+), payments (−), oldest first with a running balance.
 * Orders paid on delivery show both lines (order + payment), so the running balance stays honest.
 */
export async function customerLedger(q: Db, customerId: string): Promise<{ balance: number; entries: LedgerEntry[] }> {
  const [c] = await q
    .select({ openingBalance: customers.openingBalance, createdAt: customers.createdAt })
    .from(customers)
    .where(eq(customers.id, customerId))
    .limit(1);
  if (!c) return { balance: 0, entries: [] };
  const os = await q
    .select({ id: orders.id, ref: orders.ref, total: orders.total, at: orders.deliveredAt, channel: orders.channel })
    .from(orders)
    .where(and(eq(orders.customerId, customerId), eq(orders.status, "delivered")));
  const ps = await q
    .select({
      id: payments.id,
      ref: payments.ref,
      amount: payments.amount,
      method: payments.method,
      status: payments.status,
      at: payments.createdAt,
    })
    .from(payments)
    .where(and(eq(payments.customerId, customerId), inArray(payments.status, ["confirmed", "pending", "rejected"])))
    .orderBy(desc(payments.createdAt));

  const raw: Omit<LedgerEntry, "balance">[] = [];
  if (c.openingBalance !== 0) {
    raw.push({ kind: "opening", id: null, ref: null, at: c.createdAt.toISOString(), label: "Old listahan balance", amount: c.openingBalance, status: null });
  }
  for (const o of os) {
    raw.push({
      kind: "order",
      id: o.id,
      ref: o.ref,
      at: (o.at ?? new Date(0)).toISOString(),
      label: o.channel === "walkin" ? "Store purchase" : "Delivered order",
      amount: o.total,
      status: "delivered",
    });
  }
  for (const p of ps) {
    raw.push({
      kind: "payment",
      id: p.id,
      ref: p.ref,
      at: p.at.toISOString(),
      label: p.method === "gcash" ? "GCash payment" : "Cash payment",
      amount: p.status === "confirmed" ? -p.amount : 0,
      status: p.status,
    });
  }
  raw.sort((a, b) => a.at.localeCompare(b.at) || (a.kind === "order" ? -1 : 1));
  let running = 0;
  const entries = raw.map((e) => {
    running += e.amount;
    return { ...e, balance: running };
  });
  return { balance: running, entries };
}

/** Customer ids → balances, for lists. */
export async function balancesFor(q: Db, ids: string[]): Promise<Map<string, number>> {
  if (ids.length === 0) return new Map();
  const rows = await q.select({ id: customers.id, balance: balanceSql }).from(customers).where(inArray(customers.id, ids));
  return new Map(rows.map((r) => [r.id, Number(r.balance)]));
}
