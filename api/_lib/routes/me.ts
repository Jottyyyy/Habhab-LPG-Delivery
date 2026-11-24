/** A customer's own profile (address + map pin) and listahan. */
import { eq } from "drizzle-orm";
import { z } from "zod";
import { customers, users } from "../../../db/schema.js";
import { requireCustomer } from "../auth/guard.js";
import { requireSession } from "../auth/require-session.js";
import { db } from "../db.js";
import { json, readJson } from "../http.js";
import { customerBalance, customerLedger } from "../ledger.js";
import { customerJson } from "../views.js";
import { latField, lngField } from "./auth.js";
import { myCustomer } from "./orders.js";

export async function myProfile(req: Request): Promise<Response> {
  const s = await requireSession(req);
  requireCustomer(s);
  const d = db();
  const c = await myCustomer(d, s.userId);
  return json({ profile: customerJson(c, await customerBalance(d, c.id)) });
}

const ProfileBody = z.object({
  name: z.string().trim().min(2, "Enter your name.").max(80).optional(),
  address: z.string().trim().min(5, "Enter your full address (street, barangay).").max(300).optional(),
  landmark: z.string().trim().max(200).nullable().optional(),
  lat: latField,
  lng: lngField,
});

export async function updateMyProfile(req: Request): Promise<Response> {
  const s = await requireSession(req);
  requireCustomer(s);
  const body = ProfileBody.parse(await readJson(req));
  const d = db();
  const c = await myCustomer(d, s.userId);
  const now = new Date();
  const [u] = await d
    .update(customers)
    .set({
      ...(body.name !== undefined && { name: body.name }),
      ...(body.address !== undefined && { address: body.address }),
      ...(body.landmark !== undefined && { landmark: body.landmark || null }),
      ...(body.lat !== undefined && { lat: body.lat }),
      ...(body.lng !== undefined && { lng: body.lng }),
      updatedAt: now,
    })
    .where(eq(customers.id, c.id))
    .returning();
  if (body.name) await d.update(users).set({ name: body.name, updatedAt: now }).where(eq(users.id, s.userId));
  return json({ profile: customerJson(u, await customerBalance(d, c.id)) });
}

export async function myLedger(req: Request): Promise<Response> {
  const s = await requireSession(req);
  requireCustomer(s);
  const d = db();
  const c = await myCustomer(d, s.userId);
  const ledger = await customerLedger(d, c.id);
  return json({ ...ledger, utangAllowed: c.utangAllowed, creditLimit: c.creditLimit });
}
