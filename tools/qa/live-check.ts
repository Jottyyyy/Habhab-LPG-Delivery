/**
 * End-to-end check against the LIVE server with two throwaway QA accounts:
 * sign-up, order, accept, rider GPS, deliver, GCash + screenshot (real private Blob), POS,
 * utang, listahan, report. Afterwards run `npx tsx db/wipe-qa.ts` to remove everything it made.
 *   npx tsx tools/qa/live-check.ts [https://habhab-lpg.vercel.app]
 */
import fs from "node:fs";
import bcrypt from "bcryptjs";
import { eq } from "drizzle-orm";
import { connect } from "../../db/connect.js";
import { products, users } from "../../db/schema.js";

const BASE = (process.argv[2] ?? "https://habhab-lpg.vercel.app") + "/api";
export const QA_OWNER = "09170009998";
export const QA_CUSTOMER = "09170009999";
let pass = 0;
let fail = 0;
const ok = (name: string, cond: boolean, extra = "") => {
  if (cond) pass++;
  else fail++;
  console.log(`${cond ? "PASS" : "FAIL"}  ${name}${cond ? "" : `  ${extra}`}`);
};

type J = Record<string, any>; // eslint-disable-line @typescript-eslint/no-explicit-any -- loose JSON
async function call(method: string, path: string, token?: string, body?: unknown, raw?: Buffer): Promise<{ status: number; body: J }> {
  const headers: Record<string, string> = { "X-Client": "android" };
  if (token) headers.authorization = `Bearer ${token}`;
  if (raw) headers["content-type"] = "image/png";
  else if (body !== undefined) headers["content-type"] = "application/json";
  const res = await fetch(BASE + path, { method, headers, body: raw ? new Uint8Array(raw) : body === undefined ? undefined : JSON.stringify(body) });
  const text = await res.text();
  let parsed: J = {};
  try {
    parsed = text ? JSON.parse(text) : {};
  } catch {
    parsed = { bytes: text.length };
  }
  return { status: res.status, body: parsed };
}

async function main() {
  const { db, close } = connect();
  // Temporary store account + make two products sellable for the test (restored after).
  const pw = "qa-owner-pass-1";
  await db.delete(users).where(eq(users.phone, QA_OWNER));
  await db.insert(users).values({ name: "QA Owner", phone: QA_OWNER, role: "owner", passwordHash: await bcrypt.hash(pw, 10) });
  const ps = await db.select().from(products).orderBy(products.sort);
  const before = ps.map((p) => ({ id: p.id, price: p.price, active: p.active, stock: p.stock }));
  await db.update(products).set({ price: 95000, active: true, stock: null }).where(eq(products.id, ps[0].id));
  await db.update(products).set({ price: 45000, active: true }).where(eq(products.id, ps[4].id));

  try {
    ok("status", (await call("GET", "/status")).body.ok === true);
    const owner = (await call("POST", "/auth/login", undefined, { phone: QA_OWNER, password: pw })).body.accessToken as string;
    ok("store sign-in", Boolean(owner));
    const reg = await call("POST", "/auth/register", undefined, {
      name: "QA Customer",
      phone: QA_CUSTOMER,
      password: "qa-cust-pass",
      address: "QA address, Brgy Test",
      lat: 14.6091,
      lng: 121.0223,
    });
    ok("customer sign-up", reg.status === 201, JSON.stringify(reg.body));
    const cust = reg.body.accessToken as string;

    const store = await call("GET", "/store", cust);
    ok("customer sees products", store.body.products?.length >= 2);
    const o1 = await call("POST", "/orders", cust, { items: [{ productId: ps[0].id, qty: 2 }], paymentMethod: "cash" });
    ok("customer places order", o1.status === 201, JSON.stringify(o1.body));
    const id = o1.body.order.id;
    const board = await call("GET", "/seller/orders", owner);
    ok("store sees the new order", board.body.active?.some((o: J) => o.id === id) && board.body.counts.pending >= 1);
    ok("accept", (await call("POST", `/orders/${id}/confirm`, owner)).body.order?.status === "confirmed");
    ok("start delivery", (await call("POST", `/orders/${id}/start`, owner)).body.order?.status === "on_the_way");
    ok("rider GPS", (await call("POST", `/orders/${id}/location`, owner, { lat: 14.605, lng: 121.03 })).body.ok === true);
    const track = await call("GET", `/orders/${id}`, cust);
    ok("customer sees rider on map", track.body.order?.rider?.lat === 14.605);
    ok("delivered (cash)", (await call("POST", `/orders/${id}/deliver`, owner, { paid: "cash" })).body.order?.paid === 190000);

    const o2 = await call("POST", "/orders", cust, { items: [{ productId: ps[4].id, qty: 1 }], paymentMethod: "gcash" });
    const pay = await call("POST", "/payments/gcash", cust, { amount: 45000, gcashRef: "QA123456", orderId: o2.body.order.id });
    ok("GCash sent", pay.status === 201);
    const png = fs.readFileSync("web/icon-192.png");
    const up = await call("POST", `/uploads/proof?paymentId=${pay.body.payment.id}`, cust, undefined, png);
    ok("screenshot upload (private Blob)", up.body.payment?.hasProof === true, JSON.stringify(up.body));
    const view = await fetch(`${BASE}/proof/${pay.body.payment.id}`, { headers: { authorization: `Bearer ${owner}` } });
    ok("store sees screenshot", view.status === 200 && (await view.arrayBuffer()).byteLength === png.length);
    ok("confirm GCash", (await call("POST", `/payments/${pay.body.payment.id}/confirm`, owner)).body.payment?.status === "confirmed");
    const d2 = await call("POST", `/orders/${o2.body.order.id}/deliver`, owner, { paid: "gcash" });
    ok("delivered (GCash already paid)", d2.body.order?.paid === 45000 && d2.body.order?.pendingPaid === 0, JSON.stringify(d2.body));

    const me = await call("GET", "/me/profile", cust);
    await call("PATCH", `/customers/${me.body.profile.id}`, owner, { utangAllowed: true });
    const o3 = await call("POST", "/orders", cust, { items: [{ productId: ps[0].id, qty: 1 }], paymentMethod: "utang" });
    ok("utang order", o3.status === 201);
    await call("POST", `/orders/${o3.body.order.id}/deliver`, owner, { paid: "utang" });
    ok("listahan balance", (await call("GET", "/me/ledger", cust)).body.balance === 95000);
    const pos = await call("POST", "/pos/sales", owner, { items: [{ productId: ps[0].id, qty: 1 }], paymentMethod: "cash" });
    ok("POS walk-in sale", pos.status === 201 && pos.body.order.ref.startsWith("W-"));
    const day = new Date(Date.now() + 8 * 3600_000).toISOString().slice(0, 10);
    const rep = await call("GET", `/reports?from=${day}&to=${day}`, owner);
    ok("report", rep.body.sales?.total === 190000 + 45000 + 95000 + 95000 && rep.body.collected?.gcash === 45000 && rep.body.utang?.total === 95000, JSON.stringify(rep.body));
    ok("customer can't see the board", (await call("GET", "/seller/orders", cust)).status === 403);
  } finally {
    for (const b of before) await db.update(products).set({ price: b.price, active: b.active, stock: b.stock }).where(eq(products.id, b.id));
    await close();
  }
  console.log(`${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
