/**
 * Apply pending Drizzle migrations (db/migrations/*.sql) to DATABASE_URL.
 * Migrations in this project only ADD tables/columns; they never drop business data.
 *   npm run db:migrate
 */
import { config } from "dotenv";
import { Pool } from "@neondatabase/serverless";
import { drizzle } from "drizzle-orm/neon-serverless";
import { migrate } from "drizzle-orm/neon-serverless/migrator";

config({ path: ".env.local" });

async function main() {
  const url = process.env.DATABASE_URL_UNPOOLED || process.env.DATABASE_URL;
  if (!url) throw new Error("DATABASE_URL is not set. Run `vercel env pull .env.local`.");
  const pool = new Pool({ connectionString: url });
  await migrate(drizzle({ client: pool }), { migrationsFolder: "db/migrations" });
  await pool.end();
  console.log("Migrations applied.");
}

main().catch((e) => {
  console.error(e instanceof Error ? e.message : e);
  process.exit(1);
});
