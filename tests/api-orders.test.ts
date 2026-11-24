/* eslint-disable @typescript-eslint/no-explicit-any -- test responses are loosely typed JSON */
import { beforeAll, describe, expect, it } from "vitest";
import { eq } from "drizzle-orm";
import * as schema from "../db/schema.js";
import { addProduct, call, freshDb, makeStaff, signUp, type TestDb } from "./helpers.js";

let d: TestDb;
let owner: string;
let rider: string;
let gasul: string;
let regulator: string;

const JPEG = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3, 4, 5, 6]);

beforeAll(async () => {
  d = await freshDb();
  owner = await makeStaff(d, "owner", "09990000001");
  rider = await makeStaff(d, "staff", "09990000002", "Rider Ben");
  gasul = await addProduct(owner, "LPG 11 kg", 95000, 10);
  regulator = await addProduct(owner, "Regulator", 45000, null);
  await call("PATCH", "/settings", { token: owner, body: { deliveryFee: 2000, gcashName: "HABHAB", gcashNumber: "09978049635" } });
});

async function customerId(token: string) {
  return (await call("GET", "/me/profile", { token })).body.profile.id as string;
}

describe("customer order → delivery", () => {
  it("runs the full app order flow with live rider location and cash on delivery", async () => {
    const cust = await signUp("09171110001", "Ana");
    const store = await call("GET", "/store", { token: cust });
    expect(store.body.products.map((p: any) => p.name)).toEqual(["LPG 11 kg", "Regulator"]);
    expect(store.body.store).toMatchObject({ isOpen: true, deliveryFee: 2000, gcashNumber: "09978049635" });

    const placed = await call("POST", "/orders", { token: cust, body: { items: [{ productId: gasul, qty: 2 }], paymentMethod: "cash", notes: "Pakitawag" } });
    expect(placed.status).toBe(201);
    const order = placed.body.order;
    expect(order).toMatchObject({ ref: "O-0001", status: "pending", subtotal: 190000, deliveryFee: 2000, total: 192000, address: "123 Rizal St, Brgy. San Jose", lat: 14.6 });

    // The seller sees it.
    const board = await call("GET", "/seller/orders", { token: rider });
    expect(board.body.counts.pending).toBe(1);
    expect(board.body.active[0].id).toBe(order.id);

    expect((await call("POST", `/orders/${order.id}/confirm`, { token: rider })).body.order.status).toBe("confirmed");
    const started = await call("POST", `/orders/${order.id}/start`, { token: rider });
    expect(started.body.order).toMatchObject({ status: "on_the_way", riderName: "Rider Ben" });

    expect((await call("POST", `/orders/${order.id}/location`, { token: rider, body: { lat: 14.61, lng: 121.01 } })).body.ok).toBe(true);
    const tracking = await call("GET", `/orders/${order.id}`, { token: cust });
    expect(tracking.body.order.rider).toMatchObject({ lat: 14.61, lng: 121.01 });

    // A customer can't send a location or confirm.
    expect((await call("POST", `/orders/${order.id}/location`, { token: cust, body: { lat: 1, lng: 1 } })).status).toBe(403);

    const delivered = await call("POST", `/orders/${order.id}/deliver`, { token: rider, body: { paid: "cash" } });
    expect(delivered.body.order).toMatchObject({ status: "delivered", paid: 192000, rider: null });
    const [p] = await d.select().from(schema.products).where(eq(schema.products.id, gasul));
    expect(p.stock).toBe(8);

    const ledger = await call("GET", "/me/ledger", { token: cust });
    expect(ledger.body.balance).toBe(0);
  });

  it("refuses utang unless the owner allows it, and keeps the credit limit", async () => {
    const cust = await signUp("09171110002", "Ben");
    const no = await call("POST", "/orders", { token: cust, body: { items: [{ productId: gasul, qty: 1 }], paymentMethod: "utang" } });
    expect(no.status).toBe(403);
    expect(no.body.code).toBe("utang_not_allowed");

    const id = await customerId(cust);
    expect((await call("PATCH", `/customers/${id}`, { token: rider, body: { utangAllowed: true } })).status).toBe(403); // staff can't
    await call("PATCH", `/customers/${id}`, { token: owner, body: { utangAllowed: true, creditLimit: 150000 } });

    const ok = await call("POST", "/orders", { token: cust, body: { items: [{ productId: gasul, qty: 1 }], paymentMethod: "utang" } });
    expect(ok.status).toBe(201);
    await call("POST", `/orders/${ok.body.order.id}/deliver`, { token: rider, body: { paid: "utang" } });
    expect((await call("GET", "/me/ledger", { token: cust })).body.balance).toBe(97000);

    const over = await call("POST", "/orders", { token: cust, body: { items: [{ productId: gasul, qty: 1 }], paymentMethod: "utang" } });
    expect(over.status).toBe(409);
    expect(over.body.code).toBe("over_limit");
  });

  it("GCash: customer sends ref + screenshot, store confirms, balance goes down", async () => {
    const cust = await signUp("09171110003", "Carla");
    const id = await customerId(cust);
    await call("PATCH", `/customers/${id}`, { token: owner, body: { utangAllowed: true, openingBalance: 50000 } });
    const o = await call("POST", "/orders", { token: cust, body: { items: [{ productId: regulator, qty: 1 }], paymentMethod: "utang" } });
    await call("POST", `/orders/${o.body.order.id}/deliver`, { token: rider, body: { paid: "utang" } });
    expect((await call("GET", "/me/ledger", { token: cust })).body.balance).toBe(50000 + 45000 + 2000);

    const sent = await call("POST", "/payments/gcash", { token: cust, body: { amount: 60000, gcashRef: "1234 567 890" } });
    expect(sent.status).toBe(201);
    const payId = sent.body.payment.id;
    const up = await call("POST", `/uploads/proof?paymentId=${payId}`, { token: cust, raw: JPEG });
    expect(up.body.payment.hasProof).toBe(true);
    // Not a photo → refused
    expect((await call("POST", `/uploads/proof?paymentId=${payId}`, { token: cust, raw: new Uint8Array([1, 2, 3, 4]) })).status).toBe(415);

    // Pending doesn't lower the balance yet.
    const before = await call("GET", "/me/ledger", { token: cust });
    expect(before.body.balance).toBe(97000);
    expect(before.body.entries.at(-1)).toMatchObject({ kind: "payment", status: "pending", amount: 0 });

    const pending = await call("GET", "/payments?status=pending", { token: rider });
    expect(pending.body.payments.some((p: any) => p.id === payId && p.customerName === "Carla")).toBe(true);
    expect((await call("GET", `/proof/${payId}`, { token: rider })).status).toBe(200);

    // Other customers can't see the screenshot.
    const other = await signUp("09171110004", "Dodong");
    expect((await call("GET", `/proof/${payId}`, { token: other })).status).toBe(404);

    expect((await call("POST", `/payments/${payId}/confirm`, { token: rider })).body.payment.status).toBe("confirmed");
    expect((await call("GET", "/me/ledger", { token: cust })).body.balance).toBe(37000);

    // Store records cash for the rest.
    const cash = await call("POST", "/payments", { token: rider, body: { customerId: id, amount: 37000 } });
    expect(cash.body.balance).toBe(0);
  });

  it("keeps customers apart", async () => {
    const a = await signUp("09171110005", "Eden");
    const b = await signUp("09171110006", "Fely");
    const o = await call("POST", "/orders", { token: a, body: { items: [{ productId: regulator, qty: 1 }], paymentMethod: "cash" } });
    expect((await call("GET", `/orders/${o.body.order.id}`, { token: b })).status).toBe(404);
    expect((await call("POST", `/orders/${o.body.order.id}/cancel`, { token: b })).status).toBe(404);
    expect((await call("GET", "/customers", { token: b })).status).toBe(403);
    expect((await call("GET", "/seller/orders", { token: b })).status).toBe(403);
    expect((await call("POST", `/orders/${o.body.order.id}/confirm`, { token: b })).status).toBe(403);
    expect((await call("GET", "/me/orders", { token: b })).body.orders).toHaveLength(0);
    // Owner of the order can cancel while pending
    expect((await call("POST", `/orders/${o.body.order.id}/cancel`, { token: a })).body.order.status).toBe("cancelled");
  });

  it("customers can't cancel after the store accepts; store needs a reason", async () => {
    const a = await signUp("09171110007", "Gina");
    const o = await call("POST", "/orders", { token: a, body: { items: [{ productId: regulator, qty: 1 }], paymentMethod: "cash" } });
    await call("POST", `/orders/${o.body.order.id}/confirm`, { token: rider });
    expect((await call("POST", `/orders/${o.body.order.id}/cancel`, { token: a })).status).toBe(409);
    expect((await call("POST", `/orders/${o.body.order.id}/cancel`, { token: rider, body: {} })).status).toBe(400);
    const c = await call("POST", `/orders/${o.body.order.id}/cancel`, { token: rider, body: { reason: "Walang tao sa bahay" } });
    expect(c.body.order).toMatchObject({ status: "cancelled", cancelReason: "Walang tao sa bahay" });
  });

  it("stops orders when the store is closed or the item is out of stock", async () => {
    const a = await signUp("09171110008", "Hector");
    await call("PATCH", "/settings", { token: owner, body: { isOpen: false, closedMessage: "Sarado po ngayon" } });
    const closed = await call("POST", "/orders", { token: a, body: { items: [{ productId: gasul, qty: 1 }], paymentMethod: "cash" } });
    expect(closed.status).toBe(409);
    expect(closed.body.error).toBe("Sarado po ngayon");
    await call("PATCH", "/settings", { token: owner, body: { isOpen: true } });
    const tooMany = await call("POST", "/orders", { token: a, body: { items: [{ productId: gasul, qty: 50 }], paymentMethod: "cash" } });
    expect(tooMany.status).toBe(409);
    expect(tooMany.body.code).toBe("out_of_stock");
  });
});

describe("store side", () => {
  it("POS walk-in sale: cash and utang to a suki; owner can void", async () => {
    const before = (await d.select().from(schema.products).where(eq(schema.products.id, gasul)))[0].stock!;
    const cash = await call("POST", "/pos/sales", { token: rider, body: { items: [{ productId: gasul, qty: 1 }], paymentMethod: "cash" } });
    expect(cash.status).toBe(201);
    expect(cash.body.order).toMatchObject({ ref: "W-0001", channel: "walkin", status: "delivered", customerName: "Walk-in", total: 95000, paid: 95000 });

    const suki = await call("POST", "/customers", { token: owner, body: { name: "Aling Nena", phone: "0917 000 0001", openingBalance: 150000 } });
    expect(suki.body.customer).toMatchObject({ balance: 150000, utangAllowed: true, hasApp: false });
    const utang = await call("POST", "/pos/sales", { token: rider, body: { customerId: suki.body.customer.id, items: [{ productId: gasul, qty: 1 }], paymentMethod: "utang" } });
    expect(utang.status).toBe(201);
    const profile = await call("GET", `/customers/${suki.body.customer.id}`, { token: rider });
    expect(profile.body.customer.balance).toBe(245000);
    expect(profile.body.ledger.map((e: any) => e.kind)).toEqual(["opening", "order"]);

    expect((await call("POST", "/pos/sales", { token: rider, body: { items: [{ productId: gasul, qty: 1 }], paymentMethod: "utang" } })).status).toBe(400);

    // Staff can't void a finished sale; owner can (stock back, payment rejected).
    expect((await call("POST", `/orders/${cash.body.order.id}/cancel`, { token: rider, body: { reason: "mali" } })).status).toBe(403);
    const v = await call("POST", `/orders/${cash.body.order.id}/cancel`, { token: owner, body: { reason: "Mali ang na-type" } });
    expect(v.body.order).toMatchObject({ status: "cancelled", paid: 0 });
    const after = (await d.select().from(schema.products).where(eq(schema.products.id, gasul)))[0].stock!;
    expect(after).toBe(before - 1);
  });

  it("links a walk-in suki to the app account they register later", async () => {
    const suki = await call("POST", "/customers", { token: owner, body: { name: "Mang Tonyo", phone: "09171119999", openingBalance: 80000 } });
    const app = await signUp("09171119999", "Antonio");
    const appId = await customerId(app);
    const prof = await call("GET", `/customers/${appId}`, { token: owner });
    expect(prof.body.linkable).toEqual([{ id: suki.body.customer.id, name: "Mang Tonyo" }]);
    expect((await call("POST", `/customers/${appId}/link`, { token: rider, body: { walkinId: suki.body.customer.id } })).status).toBe(403);
    const linked = await call("POST", `/customers/${appId}/link`, { token: owner, body: { walkinId: suki.body.customer.id } });
    expect(linked.body.customer).toMatchObject({ balance: 80000, utangAllowed: true });
    expect((await call("GET", "/me/ledger", { token: app })).body.balance).toBe(80000);
    const list = await call("GET", "/customers?q=tonyo", { token: owner });
    expect(list.body.customers).toHaveLength(0); // the old record is merged away
  });

  it("owner-only screens", async () => {
    expect((await call("GET", "/reports?from=2026-01-01&to=2026-12-31", { token: rider })).status).toBe(403);
    expect((await call("POST", "/products", { token: rider, body: { name: "X item", kind: "other", price: 1 } })).status).toBe(403);
    expect((await call("PATCH", "/settings", { token: rider, body: { isOpen: false } })).status).toBe(403);
    expect((await call("GET", "/users", { token: rider })).status).toBe(403);
    expect((await call("GET", "/products", { token: rider })).status).toBe(200);
  });

  it("report adds up sales, collections and utang", async () => {
    const today = new Date(Date.now() + 8 * 3600_000).toISOString().slice(0, 10);
    const r = await call("GET", `/reports?from=${today}&to=${today}`, { token: owner });
    expect(r.status).toBe(200);
    const sales = r.body.sales;
    expect(sales.app.count).toBeGreaterThanOrEqual(3);
    expect(sales.walkin.count).toBe(1); // the voided one doesn't count
    expect(sales.total).toBe(sales.app.total + sales.walkin.total);
    expect(r.body.collected.total).toBe(r.body.collected.cash + r.body.collected.gcash);
    expect(r.body.utang.total).toBeGreaterThan(0);
    expect(r.body.items[0].name).toBe("LPG 11 kg");
  });

  it("customer forgot password: owner gives a temporary one", async () => {
    const cust = await signUp("09171112345", "Inday");
    const id = await customerId(cust);
    const reset = await call("POST", `/customers/${id}/reset-password`, { token: owner });
    expect(reset.body.temporaryPassword).toMatch(/^[a-z0-9]{4}-[a-z0-9]{4}$/);
    expect((await call("GET", "/me/profile", { token: cust })).status).toBe(401); // old session ended
    const login = await call("POST", "/auth/login", { body: { phone: "09171112345", password: reset.body.temporaryPassword } });
    expect(login.body.user.mustChangePassword).toBe(true);
  });

  it("app version + download are public", async () => {
    expect((await call("GET", "/app/download")).status).toBe(404);
    await d.update(schema.settings).set({ apkUrl: "https://example.test/Habhab-LPG.apk", apkVersion: "1.0.0" });
    const v = await call("GET", "/app/version");
    expect(v.body).toMatchObject({ latestVersion: "1.0.0", downloadUrl: "/download" });
    expect((await call("GET", "/status")).body.ok).toBe(true);
  });
});
