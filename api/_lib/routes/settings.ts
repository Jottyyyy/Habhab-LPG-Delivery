/** Store settings (owner): store info, GCash details + QR, delivery fee, open/closed. */
import { randomUUID } from "node:crypto";
import { eq } from "drizzle-orm";
import { z } from "zod";
import { settings } from "../../../db/schema.js";
import { requireOwner } from "../auth/guard.js";
import { requireSession } from "../auth/require-session.js";
import { audit } from "../audit.js";
import { db } from "../db.js";
import { json, readJson } from "../http.js";
import { normalizePhone } from "../phone.js";
import { storage } from "../storage.js";
import { getSettings } from "../store-settings.js";
import { readImage } from "./payments.js";
import { storeJson } from "./store.js";

export async function getStoreSettings(req: Request): Promise<Response> {
  const s = await requireSession(req);
  requireOwner(s);
  const st = await getSettings(db());
  return json({ settings: { ...storeJson(st), apkVersion: st.apkVersion, apkUrl: st.apkUrl } });
}

const text = (max: number) => z.string().trim().max(max).nullable().optional();

const SettingsBody = z.object({
  name: z.string().trim().min(2).max(80).optional(),
  phone: text(30),
  address: text(300),
  gcashName: text(80),
  gcashNumber: text(30),
  deliveryFee: z.number().int().min(0).max(1_000_000).optional(),
  isOpen: z.boolean().optional(),
  closedMessage: text(200),
});

export async function updateStoreSettings(req: Request): Promise<Response> {
  const s = await requireSession(req);
  requireOwner(s);
  const body = SettingsBody.parse(await readJson(req));
  const d = db();
  const before = await getSettings(d);
  const phone = (v: string | null | undefined) => (v ? (normalizePhone(v) ?? v) : null);
  const [st] = await d
    .update(settings)
    .set({
      ...(body.name !== undefined && { storeName: body.name }),
      ...(body.phone !== undefined && { storePhone: phone(body.phone) }),
      ...(body.address !== undefined && { storeAddress: body.address || null }),
      ...(body.gcashName !== undefined && { gcashName: body.gcashName || null }),
      ...(body.gcashNumber !== undefined && { gcashNumber: phone(body.gcashNumber) }),
      ...(body.deliveryFee !== undefined && { deliveryFee: body.deliveryFee }),
      ...(body.isOpen !== undefined && { isOpen: body.isOpen }),
      ...(body.closedMessage !== undefined && { closedMessage: body.closedMessage || null }),
      updatedAt: new Date(),
      updatedBy: s.userId,
    })
    .where(eq(settings.key, "main"))
    .returning();
  await audit(d, s.userId, "settings", null, "update", `${s.name} changed the store settings`, { before: storeJson(before), after: storeJson(st) });
  return json({ settings: storeJson(st) });
}

/** Upload the store's GCash QR (raw JPEG/PNG body). */
export async function uploadGcashQr(req: Request): Promise<Response> {
  const s = await requireSession(req);
  requireOwner(s);
  const { bytes, kind } = await readImage(req);
  const d = db();
  await getSettings(d);
  const blob = await storage().put(`store/gcash-qr-${randomUUID()}.${kind === "png" ? "png" : "jpg"}`, Buffer.from(bytes), `image/${kind}`);
  const [st] = await d.update(settings).set({ gcashQrPath: blob.pathname, updatedAt: new Date(), updatedBy: s.userId }).where(eq(settings.key, "main")).returning();
  await audit(d, s.userId, "settings", null, "gcash_qr", `${s.name} changed the GCash QR`);
  return json({ settings: storeJson(st) });
}
