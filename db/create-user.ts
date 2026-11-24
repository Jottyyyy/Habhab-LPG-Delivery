/**
 * Create a store account (default: the owner) with a generated temporary password.
 *
 *   npm run user:create -- --name "Habhab" --phone 09978049635
 *   npm run user:create -- --name "Rider Juan" --phone 09171234567 --role staff
 *   npm run user:create -- --phone 09978049635 --reset-password
 *
 * The password is printed once. The app asks for a new password after the first sign-in.
 */
import { config } from "dotenv";
import { Pool } from "@neondatabase/serverless";
import { drizzle } from "drizzle-orm/neon-serverless";
import { eq } from "drizzle-orm";
import bcrypt from "bcryptjs";
import { users } from "./schema.js";
import { normalizePhone } from "../api/_lib/phone.js";
import { temporaryPassword } from "../api/_lib/auth/crypto.js";

config({ path: ".env.local", quiet: true });

function arg(name: string): string | undefined {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 ? process.argv[i + 1] : undefined;
}
const flag = (name: string) => process.argv.includes(`--${name}`);

async function main() {
  const phone = normalizePhone(arg("phone") ?? "");
  const name = arg("name")?.trim();
  const role = (arg("role") ?? "owner") as "owner" | "staff";
  if (!phone) throw new Error("Pass --phone 09XXXXXXXXX");
  if (role !== "owner" && role !== "staff") throw new Error("--role must be owner or staff");
  const url = process.env.DATABASE_URL_UNPOOLED || process.env.DATABASE_URL;
  if (!url) throw new Error("DATABASE_URL is not set. Run `vercel env pull .env.local`.");

  const pool = new Pool({ connectionString: url });
  const db = drizzle({ client: pool });
  const password = temporaryPassword();
  const passwordHash = await bcrypt.hash(password, 10);

  const [existing] = await db.select().from(users).where(eq(users.phone, phone)).limit(1);
  if (existing) {
    if (!flag("reset-password")) throw new Error("That number already has an account. Use --reset-password to set a new temporary password.");
    await db.update(users).set({ passwordHash, active: true, mustChangePassword: true, updatedAt: new Date() }).where(eq(users.id, existing.id));
  } else {
    if (!name) throw new Error('Pass --name "Full Name"');
    await db.insert(users).values({ name, phone, passwordHash, role, mustChangePassword: true, device: "System" });
  }
  await pool.end();
  console.log(`${existing ? "Password reset" : `${role} account created`} for ${phone}`);
  console.log(`Temporary password: ${password}`);
  console.log("Sign in with the mobile number and this password; the app then asks for a new password.");
}

main().catch((e) => {
  console.error(e instanceof Error ? e.message : e);
  process.exit(1);
});
