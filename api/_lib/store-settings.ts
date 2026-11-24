import { eq } from "drizzle-orm";
import { settings } from "../../db/schema.js";
import type { Db } from "./db.js";

export type StoreSettings = typeof settings.$inferSelect;

/** The single settings row (made with defaults the first time). */
export async function getSettings(q: Db): Promise<StoreSettings> {
  const [row] = await q.select().from(settings).where(eq(settings.key, "main")).limit(1);
  if (row) return row;
  await q.insert(settings).values({ key: "main", storePhone: "09978049635" }).onConflictDoNothing();
  const [made] = await q.select().from(settings).where(eq(settings.key, "main")).limit(1);
  return made;
}
