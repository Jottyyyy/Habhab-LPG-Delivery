import { ApiError, errorResponse, json } from "./http.js";
import { appDownload, appVersion } from "./routes/app-info.js";
import * as auth from "./routes/auth.js";
import { backup } from "./routes/backup.js";
import * as customers from "./routes/customers.js";
import { myLedger, myProfile, updateMyProfile } from "./routes/me.js";
import * as orders from "./routes/orders.js";
import * as payments from "./routes/payments.js";
import { posSale } from "./routes/pos.js";
import { addProduct, listProducts, updateProduct } from "./routes/products.js";
import { report } from "./routes/reports.js";
import { getStoreSettings, updateStoreSettings, uploadGcashQr } from "./routes/settings.js";
import { status } from "./routes/status.js";
import { gcashQr, store } from "./routes/store.js";
import { addUser, listUsers, updateUser } from "./routes/users.js";

type Handler = (req: Request, params: Record<string, string>) => Promise<Response>;
type Route = { method: string; pattern: URLPattern; handler: Handler };

const route = (method: string, path: string, handler: Handler): Route => ({
  method,
  pattern: new URLPattern({ pathname: `/api${path}` }),
  handler,
});

/**
 * Every API endpoint. All of them check the session and role on the server, except sign-up/in,
 * refresh/logout, the health check and the app version/download (public, no data), and the
 * weekly backup (checks CRON_SECRET).
 */
const ROUTES: Route[] = [
  // accounts
  route("POST", "/auth/register", auth.register),
  route("POST", "/auth/login", auth.login),
  route("POST", "/auth/refresh", auth.refresh),
  route("POST", "/auth/logout", auth.logout),
  route("GET", "/auth/me", auth.me),
  route("POST", "/auth/password", auth.changePassword),
  // public
  route("GET", "/status", status),
  route("GET", "/app/version", appVersion),
  route("GET", "/app/download", appDownload),
  // everyone signed in
  route("GET", "/store", store),
  route("GET", "/store/gcash-qr", gcashQr),
  // customer
  route("GET", "/me/profile", myProfile),
  route("PATCH", "/me/profile", updateMyProfile),
  route("GET", "/me/ledger", myLedger),
  route("GET", "/me/orders", orders.myOrders),
  route("GET", "/me/payments", payments.myPayments),
  route("POST", "/orders", orders.placeOrder),
  route("POST", "/payments/gcash", payments.sendGcash),
  // orders (customer: own only; store: all)
  route("GET", "/orders/:id", orders.getOrder),
  route("POST", "/orders/:id/cancel", orders.cancelOrder),
  route("POST", "/orders/:id/confirm", orders.confirmOrder),
  route("POST", "/orders/:id/assign", orders.assignRider),
  route("POST", "/orders/:id/start", orders.startDelivery),
  route("POST", "/orders/:id/location", orders.riderLocation),
  route("POST", "/orders/:id/deliver", orders.deliverOrder),
  route("GET", "/seller/orders", orders.sellerOrders),
  route("POST", "/pos/sales", posSale),
  // payments + screenshots
  route("POST", "/uploads/proof", payments.uploadProof),
  route("GET", "/proof/:id", payments.viewProof),
  route("GET", "/payments", payments.listPayments),
  route("POST", "/payments", payments.recordPayment),
  route("POST", "/payments/:id/confirm", payments.confirmPayment),
  route("POST", "/payments/:id/reject", payments.rejectPayment),
  // customers (store)
  route("GET", "/customers", customers.listCustomers),
  route("POST", "/customers", customers.addCustomer),
  route("GET", "/customers/:id", customers.getCustomer),
  route("PATCH", "/customers/:id", customers.updateCustomer),
  route("POST", "/customers/:id/link", customers.linkCustomer),
  route("POST", "/customers/:id/reset-password", customers.resetCustomerPassword),
  // owner
  route("GET", "/products", listProducts),
  route("POST", "/products", addProduct),
  route("PATCH", "/products/:id", updateProduct),
  route("GET", "/reports", report),
  route("GET", "/settings", getStoreSettings),
  route("PATCH", "/settings", updateStoreSettings),
  route("POST", "/settings/gcash-qr", uploadGcashQr),
  route("GET", "/users", listUsers),
  route("POST", "/users", addUser),
  route("PATCH", "/users/:id", updateUser),
  route("GET", "/cron/backup", backup),
];

/** Single entry point for /api/* (one function = fewer cold starts). */
export async function handle(req: Request): Promise<Response> {
  try {
    const url = new URL(req.url);
    let pathname = url.pathname;
    // vercel.json rewrites /api/<path> to /api/router?path=<path>; the function may see either form.
    if (pathname === "/api/router" && url.searchParams.has("path")) pathname = `/api/${url.searchParams.get("path")}`;
    pathname = pathname.replace(/\/+$/, "") || "/";
    const method = req.method.toUpperCase();

    const matches = ROUTES.map((r) => ({ r, m: r.pattern.exec({ pathname }) })).filter((x) => x.m);
    if (matches.length === 0) throw new ApiError(404, "Not found.");
    if (method === "OPTIONS") return new Response(null, { status: 204 });

    // Exact routes win over :id routes ("/payments/gcash" before "/payments/:id").
    const hit = matches.find((x) => x.r.method === method || (method === "HEAD" && x.r.method === "GET"));
    if (!hit) {
      return json({ error: "Method not allowed." }, { status: 405, headers: { Allow: [...new Set(matches.map((x) => x.r.method))].join(", ") } });
    }
    const params = Object.fromEntries(
      Object.entries(hit.m!.pathname.groups).filter((e): e is [string, string] => typeof e[1] === "string"),
    );
    return await hit.r.handler(req, params);
  } catch (e) {
    return errorResponse(e);
  }
}
