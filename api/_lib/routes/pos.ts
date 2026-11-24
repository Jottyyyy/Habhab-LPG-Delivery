/** Walk-in sale at the store (POS). Done at once: status "delivered", stock taken out. */
import { eq } from "drizzle-orm";
import { z } from "zod";
import { customers, orders, payments } from "../../../db/schema.js";
import { nextRef } from "../../../db/refs.js";
import { requireSeller } from "../auth/guard.js";
import { requireSession } from "../auth/require-session.js";
import { audit } from "../audit.js";
import { CartItems, insertLines, moveStock, priceCart } from "../cart.js";
import { db } from "../db.js";
import { ApiError, json, readJson } from "../http.js";
import { formatPeso } from "../money.js";
import { orderJson } from "../views.js";

const SaleBody = z.object({
  customerId: z.uuid().nullable().optional(),
  items: CartItems,
  paymentMethod: z.enum(["cash", "gcash", "utang"]),
  gcashRef: z.string().trim().max(40).nullable().optional(),
  notes: z.string().trim().max(300).nullable().optional(),
});

export async function posSale(req: Request): Promise<Response> {
  const s = await requireSession(req);
  requireSeller(s);
  const body = SaleBody.parse(await readJson(req));
  const sale = await db().transaction(async (tx) => {
    let customer: typeof customers.$inferSelect | null = null;
    if (body.customerId) {
      [customer] = await tx.select().from(customers).where(eq(customers.id, body.customerId)).limit(1);
      if (!customer || !customer.active) throw new ApiError(404, "That customer was not found.");
    }
    if (body.paymentMethod === "utang" && !customer) throw new ApiError(400, "Choose the customer for an utang sale.");

    const { lines, subtotal } = await priceCart(tx, body.items);
    const now = new Date();
    const ref = await nextRef(tx, "W");
    const [o] = await tx
      .insert(orders)
      .values({
        ref,
        channel: "walkin",
        customerId: customer?.id ?? null,
        customerName: customer?.name ?? "Walk-in",
        customerPhone: customer?.phone ?? null,
        status: "delivered",
        paymentMethod: body.paymentMethod,
        notes: body.notes || null,
        subtotal,
        deliveryFee: 0,
        total: subtotal,
        riderId: s.userId,
        confirmedAt: now,
        deliveredAt: now,
        createdBy: s.userId,
        device: "Phone",
      })
      .returning();
    await insertLines(tx, o.id, s.userId, lines);
    await moveStock(tx, o.id, -1);
    if (body.paymentMethod !== "utang") {
      await tx.insert(payments).values({
        ref: await nextRef(tx, "P"),
        customerId: customer?.id ?? null,
        orderId: o.id,
        amount: subtotal,
        method: body.paymentMethod,
        gcashRef: body.gcashRef || null,
        status: "confirmed",
        note: `Store sale ${ref}`,
        reviewedBy: s.userId,
        reviewedAt: now,
        createdBy: s.userId,
        device: "Phone",
      });
    }
    await audit(tx, s.userId, "order", o.id, "pos", `${s.name} sold ${ref} to ${o.customerName} (${formatPeso(subtotal)}, ${body.paymentMethod})`);
    return o;
  });
  return json({ order: await orderJson(db(), sale) }, { status: 201 });
}
