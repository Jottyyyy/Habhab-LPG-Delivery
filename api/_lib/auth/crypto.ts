import { createHash, randomBytes } from "node:crypto";
import bcrypt from "bcryptjs";
import { SignJWT, jwtVerify } from "jose";
import { ApiError } from "../http.js";

export function sha256(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}

/** 32 random bytes, base64url (refresh tokens). */
export function randomToken(): string {
  return randomBytes(32).toString("base64url");
}

// ---------------------------------------------------------------- passwords

const COST = 10;

export function hashPassword(plain: string): Promise<string> {
  return bcrypt.hash(plain, COST);
}

// A real hash compared against when the phone is unknown, so response time is the same.
let dummyHash: Promise<string> | null = null;

export async function verifyPassword(plain: string, hash: string | null | undefined): Promise<boolean> {
  if (!hash) {
    dummyHash ??= bcrypt.hash("unknown-user-placeholder", COST);
    await bcrypt.compare(plain, await dummyHash);
    return false;
  }
  return bcrypt.compare(plain, hash);
}

/** Password rule shown on sign-up and when changing a password. */
export function passwordProblem(plain: string): string | null {
  if (plain.length < 6) return "Use at least 6 characters.";
  if (/^(.)\1+$/.test(plain) || plain === "123456" || plain === "1234567" || plain === "12345678") return "That password is too easy to guess.";
  return null;
}

/** Temporary password, e.g. "k7dq-mx3p" (unambiguous letters and digits). */
export function temporaryPassword(): string {
  const alphabet = "abcdefghjkmnpqrstuvwxyz23456789";
  const chars = Array.from(randomBytes(8), (b) => alphabet[b % alphabet.length]);
  return `${chars.slice(0, 4).join("")}-${chars.slice(4).join("")}`;
}

// ---------------------------------------------------------------- access tokens (JWT)

export type Role = "customer" | "staff" | "owner";
export const ROLES: Role[] = ["customer", "staff", "owner"];

export const ACCESS_TTL_SECONDS = 15 * 60;
const ISSUER = "habhab-lpg";
const AUDIENCE = "habhab-lpg-app";

function secretKey(): Uint8Array {
  const s = process.env.AUTH_SECRET;
  if (!s || s.length < 32) throw new Error("AUTH_SECRET is missing or too short");
  return new TextEncoder().encode(s);
}

export type AccessClaims = {
  sub: string; // user id
  sid: string; // session id
  role: Role;
};

export async function signAccessToken(c: AccessClaims, now = Date.now()): Promise<{ token: string; expiresAt: Date }> {
  const iat = Math.floor(now / 1000);
  const exp = iat + ACCESS_TTL_SECONDS;
  const token = await new SignJWT({ sid: c.sid, role: c.role })
    .setProtectedHeader({ alg: "HS256", typ: "JWT" })
    .setSubject(c.sub)
    .setIssuer(ISSUER)
    .setAudience(AUDIENCE)
    .setIssuedAt(iat)
    .setExpirationTime(exp)
    .sign(secretKey());
  return { token, expiresAt: new Date(exp * 1000) };
}

/** Verify an access token. Throws 401 when missing, expired or forged. */
export async function verifyAccessToken(token: string): Promise<AccessClaims> {
  try {
    const { payload } = await jwtVerify(token, secretKey(), { issuer: ISSUER, audience: AUDIENCE, algorithms: ["HS256"] });
    const { sub, sid, role } = payload as Record<string, unknown>;
    if (typeof sub !== "string" || typeof sid !== "string") throw new Error("bad claims");
    if (!ROLES.includes(role as Role)) throw new Error("bad claims");
    return { sub, sid, role: role as Role };
  } catch (e) {
    if (e instanceof Error && e.message.startsWith("AUTH_SECRET")) throw e;
    throw new ApiError(401, "Please sign in again.", { code: "token_invalid" });
  }
}
