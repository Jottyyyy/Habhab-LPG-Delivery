/** Test harness: a fresh in-memory Postgres (PGlite) with the real migrations, and API helpers. */
/* eslint-disable @typescript-eslint/no-explicit-any -- test responses are loosely typed JSON */
import { PGlite } from "@electric-sql/pglite";
import { drizzle } from "drizzle-orm/pglite";
import { migrate } from "drizzle-orm/pglite/migrator";
import * as schema from "../db/schema.js";
import { handle } from "../api/_lib/app.js";
import { hashPassword } from "../api/_lib/auth/crypto.js";
import { setDb, type Db } from "../api/_lib/db.js";
import { memoryStorage, setStorage } from "../api/_lib/storage.js";

process.env.AUTH_SECRET = "test-secret-for-vitest-only-0123456789abcdef";

export type TestDb = ReturnType<typeof drizzle<typeof schema>>;

export async function freshDb(): Promise<TestDb> {
  const client = new PGlite();
  const d = drizzle({ client, schema });
  await migrate(d, { migrationsFolder: "db/migrations" });
  setDb(d as unknown as Db);
  setStorage(memoryStorage());
  return d;
}

let ipCounter = 1;

export async function call(
  method: string,
  path: string,
  opts: { body?: unknown; token?: string; raw?: Uint8Array; ip?: string; headers?: Record<string, string> } = {},
): Promise<{ status: number; body: Record<string, unknown> & Record<string, any> }> {
  const headers: Record<string, string> = { "x-forwarded-for": opts.ip ?? "10.0.0.1", ...opts.headers };
  if (opts.token) headers.authorization = `Bearer ${opts.token}`;
  let body: BodyInit | undefined;
  if (opts.raw) {
    headers["content-type"] = "image/jpeg";
    body = opts.raw as BodyInit;
  } else if (opts.body !== undefined) {
    headers["content-type"] = "application/json";
    body = JSON.stringify(opts.body);
  }
  const res = await handle(new Request(`https://habhab.test/api${path}`, { method, headers, body }));
  const text = await res.text();
  let parsed: Record<string, unknown> = {};
  try {
    parsed = text ? JSON.parse(text) : {};
  } catch {
    parsed = { text };
  }
  return { status: res.status, body: parsed as never };
}

/** A unique IP per sign-up so the sign-up limit doesn't trip in tests. */
export const nextIp = () => `10.1.${Math.floor(ipCounter / 250)}.${ipCounter++ % 250}`;

export async function makeStaff(d: TestDb, role: "owner" | "staff", phone: string, name = role === "owner" ? "Habhab" : "Rider") {
  const password = "store-pass-123";
  await d.insert(schema.users).values({ name, phone, role, passwordHash: await hashPassword(password) });
  const r = await call("POST", "/auth/login", { body: { phone, password } });
  if (r.status !== 200) throw new Error(`login failed: ${JSON.stringify(r.body)}`);
  return r.body.accessToken as string;
}

export async function signUp(phone: string, name = "Juan Dela Cruz") {
  const r = await call("POST", "/auth/register", {
    ip: nextIp(),
    body: { name, phone, password: "secret-77", address: "123 Rizal St, Brgy. San Jose", landmark: "near chapel", lat: 14.6, lng: 121.0 },
  });
  if (r.status !== 201) throw new Error(`register failed: ${JSON.stringify(r.body)}`);
  return r.body.accessToken as string;
}

export async function addProduct(ownerToken: string, name: string, price: number, stock: number | null = null) {
  const r = await call("POST", "/products", { token: ownerToken, body: { name, kind: "refill", price, stock, active: true } });
  if (r.status !== 201) throw new Error(`product failed: ${JSON.stringify(r.body)}`);
  return r.body.product.id as string;
}
