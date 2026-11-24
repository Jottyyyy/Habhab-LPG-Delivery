import { ZodError } from "zod";

/** Error that becomes a JSON response with a safe, human-readable message. */
export class ApiError extends Error {
  constructor(
    public status: number,
    message: string,
    public extra?: Record<string, unknown>,
  ) {
    super(message);
  }
}

const BASE_HEADERS: Record<string, string> = {
  "Cache-Control": "no-store",
  "X-Content-Type-Options": "nosniff",
  "Referrer-Policy": "no-referrer",
};

export function json(body: unknown, init: { status?: number; headers?: HeadersInit } = {}): Response {
  const headers = new Headers(BASE_HEADERS);
  headers.set("Content-Type", "application/json; charset=utf-8");
  if (init.headers) new Headers(init.headers).forEach((v, k) => headers.set(k, v));
  return new Response(JSON.stringify(body), { status: init.status ?? 200, headers });
}

export function errorResponse(e: unknown): Response {
  if (e instanceof ApiError) return json({ error: e.message, ...e.extra }, { status: e.status });
  if (e instanceof ZodError) {
    const first = e.issues[0];
    return json(
      {
        error: first?.message && !first.message.startsWith("Invalid") ? first.message : "Some fields are not valid.",
        issues: e.issues.map((i) => ({ path: i.path.join("."), message: i.message })),
      },
      { status: 400 },
    );
  }
  console.error("API error:", safeError(e));
  return json({ error: "Something went wrong. Please try again." }, { status: 500 });
}

const MAX_JSON_BYTES = 1_000_000;

export async function readJson(req: Request, maxBytes = MAX_JSON_BYTES): Promise<unknown> {
  const type = req.headers.get("content-type") ?? "";
  if (!type.includes("application/json")) throw new ApiError(415, "Expected JSON.");
  const text = await req.text();
  if (text.length > maxBytes) throw new ApiError(413, "Request is too large.");
  try {
    return JSON.parse(text);
  } catch {
    throw new ApiError(400, "Invalid JSON.");
  }
}

/**
 * What may be logged about an error: its type and the Postgres code — never the message of a
 * failed query (Drizzle puts the SQL parameters in it: names, phone numbers, addresses).
 */
export function safeError(e: unknown): string {
  if (!(e instanceof Error)) return "unknown";
  const code = (e as { cause?: { code?: unknown } }).cause?.code;
  const pg = typeof code === "string" ? ` (${code})` : "";
  if (e.name === "DrizzleQueryError" || e.message.startsWith("Failed query")) return `query failed${pg}`;
  return `${e.name}: ${e.message.split("\n")[0].slice(0, 160)}${pg}`;
}

/** Best-effort client IP (only ever stored hashed). */
export function clientIp(req: Request): string {
  const fwd = req.headers.get("x-forwarded-for");
  return (fwd?.split(",")[0] || req.headers.get("x-real-ip") || "unknown").trim();
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** A path id that must be a UUID (anything else is "not found"). */
export function uuidParam(params: Record<string, string>, name = "id", what = "That record"): string {
  const v = params[name] ?? "";
  if (!UUID.test(v)) throw new ApiError(404, `${what} was not found.`);
  return v;
}

export const isUuid = (v: string) => UUID.test(v);
