/**
 * Weekly backup (Vercel cron, Monday 3:00 AM Manila): every business table as JSON in the
 * PRIVATE Blob store under backups/, keeping the last 8.
 * GET /api/cron/backup   Authorization: Bearer $CRON_SECRET
 * Sessions, sign-in attempts and password hashes are NOT backed up.
 */
import { timingSafeEqual } from "node:crypto";
import { auditLog, customers, orderItems, orders, payments, products, settings, users } from "../../../db/schema.js";
import { db } from "../db.js";
import { ApiError, json } from "../http.js";
import { storage } from "../storage.js";

export const KEEP_BACKUPS = 8;

function authorized(req: Request): boolean {
  const secret = process.env.CRON_SECRET ?? "";
  const got = req.headers.get("authorization") ?? "";
  const want = `Bearer ${secret}`;
  if (!secret || got.length !== want.length) return false;
  return timingSafeEqual(Buffer.from(got), Buffer.from(want));
}

export async function backup(req: Request): Promise<Response> {
  if (!authorized(req)) throw new ApiError(401, "Not allowed.");
  const d = db();
  const accounts = await d.select().from(users);
  const tables = {
    users: accounts.map(({ passwordHash: _hidden, ...u }) => u),
    customers: await d.select().from(customers),
    products: await d.select().from(products),
    orders: await d.select().from(orders),
    orderItems: await d.select().from(orderItems),
    payments: await d.select().from(payments),
    settings: await d.select().from(settings),
    auditLog: await d.select().from(auditLog),
  };
  const counts = Object.fromEntries(Object.entries(tables).map(([k, v]) => [k, v.length]));
  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  const store = storage();
  await store.put(`backups/${stamp}.json`, JSON.stringify({ madeAt: new Date().toISOString(), counts, tables }), "application/json");
  const all = await store.list("backups/");
  const sorted = all.sort((a, b) => b.pathname.localeCompare(a.pathname));
  const remove = sorted.slice(KEEP_BACKUPS).map((b) => b.url);
  await store.del(remove);
  return json({ ok: true, saved: stamp, counts, removed: remove.length });
}
