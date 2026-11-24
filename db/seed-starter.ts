/**
 * Put the starter product list in the LIVE database (only if there are no products yet).
 * Prices are empty and products hidden until the owner sets them.
 *   npx tsx db/seed-starter.ts
 */
import { count } from "drizzle-orm";
import { connect } from "./connect.js";
import { products } from "./schema.js";
import { addStarterProducts } from "./starter.js";

async function main() {
  const { db, close } = connect();
  const [n] = await db.select({ n: count() }).from(products);
  if ((n?.n ?? 0) > 0) console.log("Products already exist; nothing added.");
  else {
    await addStarterProducts(db);
    console.log("Starter products added (hidden, no price yet).");
  }
  await close();
}

main().catch((e) => {
  console.error(e instanceof Error ? e.message : e);
  process.exit(1);
});
