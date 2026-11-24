/** Products and prices. Staff can see them (POS); only the owner changes them. */
import { asc, eq } from "drizzle-orm";
import { z } from "zod";
import { products } from "../../../db/schema.js";
import { requireOwner, requireSeller } from "../auth/guard.js";
import { requireSession } from "../auth/require-session.js";
import { audit } from "../audit.js";
import { db } from "../db.js";
import { ApiError, json, readJson, uuidParam } from "../http.js";
import { productJson } from "../views.js";

export async function listProducts(req: Request): Promise<Response> {
  const s = await requireSession(req);
  requireSeller(s);
  const rows = await db().select().from(products).orderBy(asc(products.sort), asc(products.name));
  return json({ products: rows.map(productJson) });
}

const ProductBody = z.object({
  name: z.string().trim().min(2, "Enter the product name.").max(80),
  kind: z.enum(["refill", "new_tank", "accessory", "other"]),
  description: z.string().trim().max(200).nullable().optional(),
  price: z.number().int().min(0).max(10_000_000).nullable().optional(),
  stock: z.number().int().min(-9999).max(99999).nullable().optional(),
  active: z.boolean().optional(),
  sort: z.number().int().min(0).max(9999).optional(),
});

export async function addProduct(req: Request): Promise<Response> {
  const s = await requireSession(req);
  requireOwner(s);
  const body = ProductBody.parse(await readJson(req));
  if (body.active && body.price == null) throw new ApiError(400, "Set a price before showing it to customers.");
  const d = db();
  const [p] = await d
    .insert(products)
    .values({
      name: body.name,
      kind: body.kind,
      description: body.description || null,
      price: body.price ?? null,
      stock: body.stock ?? null,
      active: body.active ?? body.price != null,
      sort: body.sort ?? 0,
      createdBy: s.userId,
      device: "Phone",
    })
    .returning();
  await audit(d, s.userId, "product", p.id, "add", `${s.name} added ${p.name}`, { after: productJson(p) });
  return json({ product: productJson(p) }, { status: 201 });
}

export async function updateProduct(req: Request, params: Record<string, string>): Promise<Response> {
  const s = await requireSession(req);
  requireOwner(s);
  const id = uuidParam(params, "id", "That product");
  const body = ProductBody.partial().parse(await readJson(req));
  const d = db();
  const [before] = await d.select().from(products).where(eq(products.id, id)).limit(1);
  if (!before) throw new ApiError(404, "That product was not found.");
  const price = body.price !== undefined ? body.price : before.price;
  const active = body.active ?? before.active;
  if (active && price == null) throw new ApiError(400, "Set a price before showing it to customers.");
  const [p] = await d
    .update(products)
    .set({
      ...(body.name !== undefined && { name: body.name }),
      ...(body.kind !== undefined && { kind: body.kind }),
      ...(body.description !== undefined && { description: body.description || null }),
      ...(body.price !== undefined && { price: body.price }),
      ...(body.stock !== undefined && { stock: body.stock }),
      ...(body.active !== undefined && { active: body.active }),
      ...(body.sort !== undefined && { sort: body.sort }),
      updatedAt: new Date(),
    })
    .where(eq(products.id, id))
    .returning();
  await audit(d, s.userId, "product", id, "update", `${s.name} updated ${p.name}`, { before: productJson(before), after: productJson(p) });
  return json({ product: productJson(p) });
}
