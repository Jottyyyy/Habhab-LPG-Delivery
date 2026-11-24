/**
 * Local test server: the real API on a throwaway in-memory database, plus the download page.
 * It never touches the live database (DATABASE_URL is ignored).
 *
 *   npm run dev:local                    http://localhost:8787
 *   npm run dev:local -- --seed          demo products with prices + a sample suki
 *   npm run dev:local -- --owner         also create a test owner (prints its login)
 *
 * Android emulator: build the app with --dart-define=API_BASE_URL=http://10.0.2.2:8787/api
 * (debug builds allow plain http to the emulator host only).
 */
import fs from "node:fs";
import http from "node:http";
import path from "node:path";
import { randomBytes } from "node:crypto";
import { PGlite } from "@electric-sql/pglite";
import { drizzle } from "drizzle-orm/pglite";
import { migrate } from "drizzle-orm/pglite/migrator";
import * as schema from "../db/schema.js";
import { addStarterProducts } from "../db/starter.js";
import { handle } from "../api/_lib/app.js";
import { hashPassword } from "../api/_lib/auth/crypto.js";
import { setDb, type Db } from "../api/_lib/db.js";
import { memoryStorage, setStorage } from "../api/_lib/storage.js";

const PORT = Number(process.env.PORT ?? 8787);
const WEB_ROOT = path.resolve("web");
const TYPES: Record<string, string> = { ".html": "text/html; charset=utf-8", ".png": "image/png", ".css": "text/css", ".ico": "image/x-icon" };

delete process.env.DATABASE_URL;
delete process.env.DATABASE_URL_UNPOOLED;
process.env.AUTH_SECRET ??= randomBytes(32).toString("hex");

async function readBody(req: http.IncomingMessage): Promise<Buffer> {
  const chunks: Buffer[] = [];
  for await (const c of req) chunks.push(c as Buffer);
  return Buffer.concat(chunks);
}

async function api(req: http.IncomingMessage, res: http.ServerResponse, url: URL) {
  const headers = new Headers();
  for (const [k, v] of Object.entries(req.headers)) {
    if (typeof v === "string") headers.set(k, v);
    else if (Array.isArray(v)) v.forEach((x) => headers.append(k, x));
  }
  headers.set("x-forwarded-for", req.socket.remoteAddress ?? "127.0.0.1");
  const hasBody = req.method !== "GET" && req.method !== "HEAD";
  const r = await handle(new Request(url, { method: req.method, headers, body: hasBody ? new Uint8Array(await readBody(req)) : undefined }));
  res.statusCode = r.status;
  r.headers.forEach((v, k) => res.setHeader(k, v));
  res.end(Buffer.from(await r.arrayBuffer()));
  if (!url.pathname.endsWith("/location") && !url.pathname.endsWith("/seller/orders")) {
    console.log(`${new Date().toISOString().slice(11, 19)} ${req.method} ${url.pathname} ${r.status}`);
  }
}

function web(res: http.ServerResponse, url: URL) {
  let file = path.join(WEB_ROOT, decodeURIComponent(url.pathname));
  if (!file.startsWith(WEB_ROOT)) file = WEB_ROOT;
  if (!fs.existsSync(file) || fs.statSync(file).isDirectory()) file = path.join(WEB_ROOT, "index.html");
  if (!fs.existsSync(file)) {
    res.statusCode = 404;
    res.end("Not found");
    return;
  }
  res.setHeader("Content-Type", TYPES[path.extname(file)] ?? "application/octet-stream");
  res.setHeader("Cache-Control", "no-store");
  fs.createReadStream(file).pipe(res);
}

async function main() {
  const client = new PGlite();
  const db = drizzle({ client, schema });
  await migrate(db, { migrationsFolder: "db/migrations" });
  setDb(db as unknown as Db);
  // Screenshots and backups stay in memory (never the real Blob store).
  setStorage(memoryStorage());

  if (process.argv.includes("--seed")) {
    await addStarterProducts(db, { sample: true });
    await db.insert(schema.settings).values({
      key: "main",
      storePhone: "09978049635",
      storeAddress: "Sample address (local test)",
      gcashName: "HABHAB LPG",
      gcashNumber: "09978049635",
      deliveryFee: 0,
    });
    await db.insert(schema.customers).values({ name: "Aling Nena (suki)", phone: "09170000001", address: "Purok 3", openingBalance: 150000, utangAllowed: true });
    console.log("Demo products, store settings and a sample suki loaded.");
  }
  if (process.argv.includes("--owner")) {
    const password = randomBytes(6).toString("base64url");
    await db.insert(schema.users).values({ name: "Local Owner", phone: "09990000000", passwordHash: await hashPassword(password), role: "owner" });
    console.log(`Test owner: 09990000000 / ${password} (local database only)`);
  }

  http
    .createServer((req, res) => {
      const url = new URL(req.url ?? "/", `http://${req.headers.host ?? `localhost:${PORT}`}`);
      const isApi = url.pathname === "/api" || url.pathname.startsWith("/api/");
      if (url.pathname === "/download") url.pathname = "/api/app/download";
      const work = isApi || url.pathname === "/api/app/download" ? api(req, res, url) : Promise.resolve(web(res, url));
      work.catch((e) => {
        console.error("dev server error:", e instanceof Error ? e.message : e);
        if (!res.headersSent) res.statusCode = 500;
        res.end();
      });
    })
    .listen(PORT, "0.0.0.0", () => console.log(`Local server: http://localhost:${PORT}  (emulator: http://10.0.2.2:${PORT})`));
}

main().catch((e) => {
  console.error(e instanceof Error ? e.message : e);
  process.exit(1);
});
