/** Turning a cart (product ids + quantities) into priced order lines, with stock changes. */
import { eq, inArray, sql } from "drizzle-orm";
import { z } from "zod";
import { orderItems, products } from "../../db/schema.js";
import type { Db } from "./db.js";
import { ApiError } from "./http.js";

export const CartItems = z
  .array(z.object({ productId: z.uuid(), qty: z.number().int().min(1).max(99) }))
  .min(1, "Add at least one item.")
  .max(30);

export type PricedLine = { productId: string; name: string; unitPrice: number; qty: number; lineTotal: number };

/** Price the cart from the database (never trust prices from the phone). */
export async function priceCart(q: Db, items: z.infer<typeof CartItems>): Promise<{ lines: PricedLine[]; subtotal: number }> {
  const merged = new Map<string, number>();
  for (const i of items) merged.set(i.productId, (merged.get(i.productId) ?? 0) + i.qty);
  const rows = await q.select().from(products).where(inArray(products.id, [...merged.keys()]));
  const lines: PricedLine[] = [];
  for (const [productId, qty] of merged) {
    const p = rows.find((r) => r.id === productId);
    if (!p || !p.active || p.price == null) throw new ApiError(409, "An item in your cart is no longer available. Please check your cart.", { code: "product_unavailable" });
    if (p.stock != null && p.stock < qty) {
      throw new ApiError(409, p.stock <= 0 ? `${p.name} is out of stock.` : `Only ${p.stock} left of ${p.name}.`, { code: "out_of_stock" });
    }
    lines.push({ productId, name: p.name, unitPrice: p.price, qty, lineTotal: p.price * qty });
  }
  return { lines, subtotal: lines.reduce((s, l) => s + l.lineTotal, 0) };
}

export async function insertLines(q: Db, orderId: string, actorId: string, lines: PricedLine[]) {
  await q.insert(orderItems).values(lines.map((l) => ({ ...l, orderId, createdBy: actorId, device: "Phone" })));
}

/** Take items out of stock (sale done) or put them back (sale voided). Untracked stock stays null. */
export async function moveStock(q: Db, orderId: string, direction: -1 | 1) {
  const lines = await q.select({ productId: orderItems.productId, qty: orderItems.qty }).from(orderItems).where(eq(orderItems.orderId, orderId));
  for (const l of lines) {
    if (!l.productId) continue;
    await q
      .update(products)
      .set({ stock: sql`case when ${products.stock} is null then null else ${products.stock} + ${direction * l.qty} end`, updatedAt: new Date() })
      .where(eq(products.id, l.productId));
  }
}
