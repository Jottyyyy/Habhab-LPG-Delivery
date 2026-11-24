/**
 * Starter product list (LPG store). Prices are left empty and the products hidden until the
 * owner sets his real prices in the app (Products). `sample: true` adds demo prices for the
 * local test server only.
 */
import type { PgDatabase, PgQueryResultHKT } from "drizzle-orm/pg-core";
import { products } from "./schema.js";

// eslint-disable-next-line @typescript-eslint/no-explicit-any -- any Drizzle Postgres db
type AnyDb = PgDatabase<PgQueryResultHKT, any>;

const STARTER: { name: string; kind: "refill" | "new_tank" | "accessory"; description: string; demoPrice: number; demoStock: number | null }[] = [
  { name: "LPG 11 kg (refill / palit)", kind: "refill", description: "Exchange your empty 11 kg tank for a full one.", demoPrice: 95000, demoStock: 20 },
  { name: "LPG 2.7 kg (refill / palit)", kind: "refill", description: "Small tank for single burner stoves.", demoPrice: 32000, demoStock: 10 },
  { name: "LPG 22 kg (refill / palit)", kind: "refill", description: "Big tank for stores and eateries.", demoPrice: 185000, demoStock: 4 },
  { name: "LPG 11 kg with new tank", kind: "new_tank", description: "Full 11 kg tank with a new cylinder.", demoPrice: 280000, demoStock: 5 },
  { name: "Regulator", kind: "accessory", description: "Gas regulator.", demoPrice: 45000, demoStock: null },
  { name: "Hose with clamps", kind: "accessory", description: "LPG hose (1.5 m) with 2 clamps.", demoPrice: 18000, demoStock: null },
];

export async function addStarterProducts(db: AnyDb, opts: { sample?: boolean } = {}) {
  await db.insert(products).values(
    STARTER.map((p, i) => ({
      name: p.name,
      kind: p.kind,
      description: p.description,
      price: opts.sample ? p.demoPrice : null,
      stock: opts.sample ? p.demoStock : null,
      active: Boolean(opts.sample),
      sort: i * 10,
    })),
  );
}
