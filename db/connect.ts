import { config } from "dotenv";
import { Pool } from "@neondatabase/serverless";
import { drizzle } from "drizzle-orm/neon-serverless";
import * as schema from "./schema.js";

config({ path: ".env.local", quiet: true });

/** Database connection for scripts (direct, non-pooled URL when available). */
export function connect() {
  const url = process.env.DATABASE_URL_UNPOOLED || process.env.DATABASE_URL;
  if (!url) throw new Error("DATABASE_URL is not set. Run `vercel env pull .env.local`.");
  const pool = new Pool({ connectionString: url });
  return { db: drizzle({ client: pool, schema }), close: () => pool.end() };
}
