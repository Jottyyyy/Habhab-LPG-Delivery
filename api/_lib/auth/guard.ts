import { ApiError } from "../http.js";
import { verifyAccessToken, type Role } from "./crypto.js";

export type Auth = { userId: string; sessionId: string; role: Role };

/** Authenticate a request: the Android app sends `Authorization: Bearer <access token>`. */
export async function authenticate(req: Request): Promise<Auth> {
  const header = req.headers.get("authorization");
  if (!header) throw new ApiError(401, "Please sign in again.", { code: "token_missing" });
  const m = /^Bearer\s+(.+)$/i.exec(header);
  if (!m) throw new ApiError(401, "Please sign in again.", { code: "token_invalid" });
  const claims = await verifyAccessToken(m[1].trim());
  return { userId: claims.sub, sessionId: claims.sid, role: claims.role };
}

/** Owner or staff (the seller side of the app). */
export function requireSeller(auth: { role: Role }) {
  if (auth.role !== "owner" && auth.role !== "staff") throw new ApiError(403, "Only the store can do this.");
}

export function requireOwner(auth: { role: Role }) {
  if (auth.role !== "owner") throw new ApiError(403, "Only the owner can do this.");
}

export function requireCustomer(auth: { role: Role }) {
  if (auth.role !== "customer") throw new ApiError(403, "This is for customer accounts.");
}
