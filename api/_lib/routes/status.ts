import { sql } from "drizzle-orm";
import { db } from "../db.js";
import { json } from "../http.js";

/** Public health check: the server and the database answer. No business data. */
export async function status(_req: Request): Promise<Response> {
  await db().execute(sql`select 1`);
  return json({ ok: true, serverTime: new Date().toISOString() });
}
