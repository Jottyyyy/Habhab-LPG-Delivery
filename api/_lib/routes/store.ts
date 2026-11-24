/** What every signed-in user sees: store info (open/closed, GCash, delivery fee) and products for sale. */
import { and, asc, eq, isNotNull } from "drizzle-orm";
import { products } from "../../../db/schema.js";
import { requireSession } from "../auth/require-session.js";
import { db } from "../db.js";
import { ApiError, json } from "../http.js";
import { storage } from "../storage.js";
import { getSettings, type StoreSettings } from "../store-settings.js";
import { productJson } from "../views.js";

export function storeJson(s: StoreSettings) {
  return {
    name: s.storeName,
    phone: s.storePhone,
    address: s.storeAddress,
    isOpen: s.isOpen,
    closedMessage: s.closedMessage,
    deliveryFee: s.deliveryFee,
    gcashName: s.gcashName,
    gcashNumber: s.gcashNumber,
    hasGcashQr: Boolean(s.gcashQrPath),
  };
}

export async function store(req: Request): Promise<Response> {
  await requireSession(req);
  const d = db();
  const s = await getSettings(d);
  const rows = await d
    .select()
    .from(products)
    .where(and(eq(products.active, true), isNotNull(products.price)))
    .orderBy(asc(products.sort), asc(products.name));
  return json({ store: storeJson(s), products: rows.map(productJson) });
}

/** The store's GCash QR image (signed-in users only). */
export async function gcashQr(req: Request): Promise<Response> {
  await requireSession(req);
  const s = await getSettings(db());
  if (!s.gcashQrPath) throw new ApiError(404, "No GCash QR yet.");
  const file = await storage().get(s.gcashQrPath);
  if (!file) throw new ApiError(404, "No GCash QR yet.");
  return new Response(file.stream, {
    headers: { "Content-Type": file.contentType ?? "image/jpeg", "Cache-Control": "private, no-store", "X-Content-Type-Options": "nosniff" },
  });
}
