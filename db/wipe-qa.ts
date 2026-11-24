/**
 * Remove test data from the LIVE database before handover (pre-launch only): every order,
 * payment, customer, session and audit line, the QA accounts, the screenshots in Blob, and
 * reset the numbering (first real order = O-0001). Products, prices and settings stay.
 * Refuses if there is any real account (anyone other than the QA accounts / the owner).
 *   npx tsx db/wipe-qa.ts --yes-pre-launch
 */
import { inArray, ne, notInArray, sql } from "drizzle-orm";
import { del, list } from "@vercel/blob";
import { connect } from "./connect.js";
import { auditLog, customers, loginAttempts, orderItems, orders, payments, refCounters, sessions, users } from "./schema.js";

const QA = ["09170009998", "09170009999"];

async function main() {
  if (!process.argv.includes("--yes-pre-launch")) throw new Error("Pass --yes-pre-launch (this deletes all orders and customers).");
  const { db, close } = connect();
  const real = await db.select({ phone: users.phone, role: users.role }).from(users).where(notInArray(users.phone, QA));
  const realCustomers = real.filter((u) => u.role === "customer");
  if (realCustomers.length > 0) throw new Error(`Refusing: ${realCustomers.length} real customer account(s) exist. The app is live.`);
  await db.delete(orderItems);
  await db.delete(payments);
  await db.delete(orders);
  await db.delete(customers);
  await db.delete(sessions).where(inArray(sessions.userId, db.select({ id: users.id }).from(users).where(inArray(users.phone, QA))));
  await db.delete(users).where(inArray(users.phone, QA));
  await db.delete(loginAttempts);
  await db.delete(auditLog).where(ne(auditLog.entity, "settings"));
  await db.delete(refCounters);
  let removed = 0;
  if (process.env.BLOB_READ_WRITE_TOKEN) {
    const blobs = await list({ prefix: "proofs/" });
    if (blobs.blobs.length) await del(blobs.blobs.map((b) => b.url));
    removed = blobs.blobs.length;
  }
  const [n] = await db.select({ n: sql<number>`count(*)::int` }).from(orders);
  await close();
  console.log(`Test data removed (orders left: ${n.n}, screenshots removed: ${removed}). Store accounts kept: ${real.map((u) => u.phone).join(", ") || "none"}.`);
}

main().catch((e) => {
  console.error(e instanceof Error ? e.message : e);
  process.exit(1);
});
