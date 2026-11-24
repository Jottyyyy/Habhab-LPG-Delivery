import { Pool } from "@neondatabase/serverless";
import { drizzle } from "drizzle-orm/neon-serverless";
import type { PgDatabase, PgQueryResultHKT } from "drizzle-orm/pg-core";
import * as schema from "../../db/schema.js";

/** Drizzle database (Neon in production, PGlite in tests). */
export type Db = PgDatabase<PgQueryResultHKT, typeof schema>;

let current: Db | null = null;

/**
 * Drizzle over Neon's WebSocket Pool (supports interactive transactions).
 * One pool per function instance; Fluid Compute reuses it across requests.
 */
export function db(): Db {
  if (!current) {
    const url = process.env.DATABASE_URL;
    if (!url) throw new Error("DATABASE_URL is not set");
    current = drizzle({ client: new Pool({ connectionString: url, max: 5 }), schema }) as unknown as Db;
  }
  return current;
}

/** Tests swap in an in-memory database. */
export function setDb(next: Db | null) {
  current = next;
}

export { schema };
