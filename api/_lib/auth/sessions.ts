import { and, count, eq, gt, isNull, or } from "drizzle-orm";
import { loginAttempts, sessions, users } from "../../../db/schema.js";
import { db } from "../db.js";
import { randomToken, sha256, type Role } from "./crypto.js";

export const REFRESH_DAYS = 90;
const DAY = 24 * 60 * 60 * 1000;

/** A rotated-away refresh token still works this long (phone lost the response on bad signal). */
export const ROTATION_GRACE_MS = 10 * 60 * 1000;

export type SessionInfo = {
  sessionId: string;
  userId: string;
  name: string;
  phone: string;
  role: Role;
  mustChangePassword: boolean;
};

export type IssuedRefresh = SessionInfo & { refreshToken: string; refreshExpiresAt: Date };

type UserLike = { id: string; name: string; phone: string; role: Role; mustChangePassword: boolean };

export async function createSession(user: UserLike, now = new Date()): Promise<IssuedRefresh> {
  const refreshToken = randomToken();
  const refreshExpiresAt = new Date(now.getTime() + REFRESH_DAYS * DAY);
  const [row] = await db()
    .insert(sessions)
    .values({ tokenHash: sha256(refreshToken), userId: user.id, device: "Phone", createdBy: user.id, expiresAt: refreshExpiresAt, lastSeenAt: now })
    .returning({ id: sessions.id });
  return {
    sessionId: row.id,
    userId: user.id,
    name: user.name,
    phone: user.phone,
    role: user.role,
    mustChangePassword: user.mustChangePassword,
    refreshToken,
    refreshExpiresAt,
  };
}

const sessionUserColumns = {
  sessionId: sessions.id,
  userId: users.id,
  name: users.name,
  phone: users.phone,
  role: users.role,
  mustChangePassword: users.mustChangePassword,
};

/**
 * Exchange a refresh token for a new one (rotation, 90-day sliding expiry).
 * - Current token: rotate.
 * - Previous token within the grace window: rotate again (lost response).
 * - Previous token after the grace window: someone replayed an old token, so the session is revoked.
 * Returns null when the token is unknown, expired, revoked or the user is turned off.
 */
export async function rotateRefreshToken(presented: string | null | undefined, now = new Date()): Promise<IssuedRefresh | null> {
  if (!presented || presented.length < 20 || presented.length > 200) return null;
  const hash = sha256(presented);
  const [row] = await db()
    .select({ ...sessionUserColumns, tokenHash: sessions.tokenHash, prevTokenHash: sessions.prevTokenHash, rotatedAt: sessions.rotatedAt })
    .from(sessions)
    .innerJoin(users, eq(users.id, sessions.userId))
    .where(
      and(
        or(eq(sessions.tokenHash, hash), eq(sessions.prevTokenHash, hash)),
        isNull(sessions.revokedAt),
        gt(sessions.expiresAt, now),
        eq(users.active, true),
      ),
    )
    .limit(1);
  if (!row) return null;

  const isCurrent = row.tokenHash === hash;
  if (!isCurrent) {
    const recent = row.rotatedAt && now.getTime() - row.rotatedAt.getTime() <= ROTATION_GRACE_MS;
    if (!recent) {
      await revokeSession(row.sessionId, now);
      return null;
    }
  }

  const refreshToken = randomToken();
  const refreshExpiresAt = new Date(now.getTime() + REFRESH_DAYS * DAY);
  // Only rotate if nobody else rotated this session in the meantime (concurrent refresh).
  const updated = await db()
    .update(sessions)
    .set({
      tokenHash: sha256(refreshToken),
      prevTokenHash: isCurrent ? hash : row.prevTokenHash,
      rotatedAt: isCurrent ? now : row.rotatedAt,
      expiresAt: refreshExpiresAt,
      lastSeenAt: now,
      updatedAt: now,
    })
    .where(and(eq(sessions.id, row.sessionId), eq(sessions.tokenHash, row.tokenHash)))
    .returning({ id: sessions.id });
  if (updated.length === 0) return null;

  return {
    sessionId: row.sessionId,
    userId: row.userId,
    name: row.name,
    phone: row.phone,
    role: row.role,
    mustChangePassword: row.mustChangePassword,
    refreshToken,
    refreshExpiresAt,
  };
}

/** Find the session for a refresh token without rotating (used by logout). */
export async function sessionIdForRefresh(presented: string | null | undefined): Promise<string | null> {
  if (!presented || presented.length < 20 || presented.length > 200) return null;
  const hash = sha256(presented);
  const [row] = await db()
    .select({ id: sessions.id })
    .from(sessions)
    .where(and(or(eq(sessions.tokenHash, hash), eq(sessions.prevTokenHash, hash)), isNull(sessions.revokedAt)))
    .limit(1);
  return row?.id ?? null;
}

export async function revokeSession(sessionId: string, now = new Date()) {
  await db()
    .update(sessions)
    .set({ revokedAt: now, updatedAt: now })
    .where(and(eq(sessions.id, sessionId), isNull(sessions.revokedAt)));
}

/** Sign a user out everywhere (password reset, account turned off). */
export async function revokeAllSessions(userId: string, exceptSessionId?: string, now = new Date()) {
  const rows = await db()
    .select({ id: sessions.id })
    .from(sessions)
    .where(and(eq(sessions.userId, userId), isNull(sessions.revokedAt)));
  for (const r of rows) if (r.id !== exceptSessionId) await revokeSession(r.id, now);
}

/** The user behind a valid session, or null if it was revoked or the user turned off. */
export async function activeSessionUser(sessionId: string, now = new Date()): Promise<SessionInfo | null> {
  const [row] = await db()
    .select(sessionUserColumns)
    .from(sessions)
    .innerJoin(users, eq(users.id, sessions.userId))
    .where(and(eq(sessions.id, sessionId), isNull(sessions.revokedAt), gt(sessions.expiresAt, now), eq(users.active, true)))
    .limit(1);
  return row ?? null;
}

export async function findUserByPhone(phone: string) {
  const [user] = await db().select().from(users).where(eq(users.phone, phone)).limit(1);
  return user ?? null;
}

// ---------------------------------------------------------------- rate limits

export const LOCK_MINUTES = 10;
export const MAX_FAILS_PER_PHONE = 5;
export const MAX_FAILS_PER_IP = 20;
/** Sign-ups per IP per hour (no SMS check, so keep strangers from making hundreds of accounts). */
export const MAX_SIGNUPS_PER_IP_HOUR = 5;
export const SIGNUP_KEY = "(signup)";

function ipHash(ip: string) {
  // Salted so the stored value cannot be matched back to an IP without the server secret.
  return sha256(`${process.env.AUTH_SECRET ?? "habhab"}:ip:${ip}`);
}

/** True when this phone or IP has too many failed sign-ins in the last 10 minutes. */
export async function isLockedOut(phone: string, ip: string, now = new Date()): Promise<boolean> {
  const since = new Date(now.getTime() - LOCK_MINUTES * 60_000);
  const [byPhone] = await db()
    .select({ n: count() })
    .from(loginAttempts)
    .where(and(eq(loginAttempts.loginKey, phone), eq(loginAttempts.success, false), gt(loginAttempts.at, since)));
  if ((byPhone?.n ?? 0) >= MAX_FAILS_PER_PHONE) return true;
  const [byIp] = await db()
    .select({ n: count() })
    .from(loginAttempts)
    .where(and(eq(loginAttempts.ipHash, ipHash(ip)), eq(loginAttempts.success, false), gt(loginAttempts.at, since)));
  return (byIp?.n ?? 0) >= MAX_FAILS_PER_IP;
}

export async function tooManySignups(ip: string, now = new Date()): Promise<boolean> {
  const since = new Date(now.getTime() - 60 * 60_000);
  const [n] = await db()
    .select({ n: count() })
    .from(loginAttempts)
    .where(and(eq(loginAttempts.loginKey, SIGNUP_KEY), eq(loginAttempts.ipHash, ipHash(ip)), gt(loginAttempts.at, since)));
  return (n?.n ?? 0) >= MAX_SIGNUPS_PER_IP_HOUR;
}

export async function recordAttempt(loginKey: string, ip: string, success: boolean, userId?: string) {
  await db()
    .insert(loginAttempts)
    .values({ loginKey, ipHash: ipHash(ip), success, createdBy: userId ?? null, device: "Phone" });
}
