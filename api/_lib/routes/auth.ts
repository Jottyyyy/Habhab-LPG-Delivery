/**
 * Sign up (customers), sign in, refresh, sign out, "who am I" and change password.
 * Sign-in name = mobile number. Tokens go back in the JSON body (the Android app keeps
 * them in secure storage).
 */
import { eq } from "drizzle-orm";
import { z } from "zod";
import { customers, users } from "../../../db/schema.js";
import { hashPassword, passwordProblem, signAccessToken, verifyPassword } from "../auth/crypto.js";
import { authenticate } from "../auth/guard.js";
import { requireSession } from "../auth/require-session.js";
import {
  LOCK_MINUTES,
  SIGNUP_KEY,
  activeSessionUser,
  createSession,
  findUserByPhone,
  isLockedOut,
  recordAttempt,
  revokeAllSessions,
  revokeSession,
  rotateRefreshToken,
  sessionIdForRefresh,
  tooManySignups,
  type IssuedRefresh,
  type SessionInfo,
} from "../auth/sessions.js";
import { audit } from "../audit.js";
import { db } from "../db.js";
import { ApiError, clientIp, json, readJson } from "../http.js";
import { normalizePhone } from "../phone.js";

export const phoneField = z
  .string()
  .max(30)
  .transform((v, ctx) => {
    const p = normalizePhone(v);
    if (!p) {
      ctx.addIssue({ code: "custom", message: "Enter a mobile number like 0917 123 4567." });
      return z.NEVER;
    }
    return p;
  });

export const latField = z.number().min(-90).max(90).nullable().optional();
export const lngField = z.number().min(-180).max(180).nullable().optional();

const userJson = (s: SessionInfo) => ({
  id: s.userId,
  name: s.name,
  phone: s.phone,
  role: s.role,
  mustChangePassword: s.mustChangePassword,
});

export async function tokenResponse(s: IssuedRefresh, status = 200): Promise<Response> {
  const access = await signAccessToken({ sub: s.userId, sid: s.sessionId, role: s.role });
  return json(
    {
      user: userJson(s),
      accessToken: access.token,
      accessExpiresAt: access.expiresAt.toISOString(),
      refreshToken: s.refreshToken,
      refreshExpiresAt: s.refreshExpiresAt.toISOString(),
    },
    { status },
  );
}

// ---------------------------------------------------------------- sign up (customers)

const RegisterBody = z.object({
  name: z.string().trim().min(2, "Enter your name.").max(80),
  phone: phoneField,
  password: z.string().max(200),
  address: z.string().trim().min(5, "Enter your full address (street, barangay).").max(300),
  landmark: z.string().trim().max(200).nullable().optional(),
  lat: latField,
  lng: lngField,
});

export async function register(req: Request): Promise<Response> {
  const body = RegisterBody.parse(await readJson(req));
  const ip = clientIp(req);
  const problem = passwordProblem(body.password);
  if (problem) throw new ApiError(400, problem);
  if (await tooManySignups(ip)) throw new ApiError(429, "Too many new accounts from this connection. Please try again later.");
  if (await findUserByPhone(body.phone)) {
    throw new ApiError(409, "That number already has an account. Sign in instead.", { code: "phone_taken" });
  }

  const passwordHash = await hashPassword(body.password);
  const user = await db().transaction(async (tx) => {
    const [u] = await tx
      .insert(users)
      .values({ name: body.name, phone: body.phone, passwordHash, role: "customer", device: "Phone" })
      .returning();
    await tx.insert(customers).values({
      userId: u.id,
      createdBy: u.id,
      device: "Phone",
      name: body.name,
      phone: body.phone,
      address: body.address,
      landmark: body.landmark || null,
      lat: body.lat ?? null,
      lng: body.lng ?? null,
    });
    await audit(tx, u.id, "user", u.id, "signup", `${body.name} made a customer account`);
    return u;
  });
  await recordAttempt(SIGNUP_KEY, ip, true, user.id);
  return tokenResponse(await createSession(user), 201);
}

// ---------------------------------------------------------------- sign in / refresh / sign out

const LoginBody = z.object({ phone: phoneField, password: z.string().min(1).max(200) });

export async function login(req: Request): Promise<Response> {
  const parsed = LoginBody.safeParse(await readJson(req));
  if (!parsed.success) throw new ApiError(401, "Wrong mobile number or password.");
  const body = parsed.data;
  const ip = clientIp(req);

  if (await isLockedOut(body.phone, ip)) {
    throw new ApiError(429, `Too many wrong tries. Please wait ${LOCK_MINUTES} minutes and try again.`);
  }
  const user = await findUserByPhone(body.phone);
  const ok = await verifyPassword(body.password, user?.active ? user.passwordHash : null);
  if (!user || !ok) {
    await recordAttempt(body.phone, ip, false);
    throw new ApiError(401, "Wrong mobile number or password.");
  }
  await recordAttempt(body.phone, ip, true, user.id);
  return tokenResponse(await createSession(user));
}

const RefreshBody = z.object({ refreshToken: z.string().min(20).max(200) });

export async function refresh(req: Request): Promise<Response> {
  const parsed = RefreshBody.safeParse(await readJson(req).catch(() => null));
  const rotated = await rotateRefreshToken(parsed.success ? parsed.data.refreshToken : null);
  if (!rotated) return json({ error: "Please sign in again.", code: "refresh_invalid" }, { status: 401 });
  return tokenResponse(rotated);
}

export async function logout(req: Request): Promise<Response> {
  let sessionId: string | null = null;
  try {
    sessionId = (await authenticate(req)).sessionId;
  } catch {
    // Access token expired: fall back to the refresh token.
    const parsed = RefreshBody.safeParse(await readJson(req).catch(() => null));
    sessionId = await sessionIdForRefresh(parsed.success ? parsed.data.refreshToken : null);
  }
  if (sessionId) await revokeSession(sessionId);
  return json({ ok: true });
}

export async function me(req: Request): Promise<Response> {
  const auth = await authenticate(req);
  const s = await activeSessionUser(auth.sessionId);
  if (!s) throw new ApiError(401, "Please sign in again.", { code: "session_ended" });
  return json({ user: userJson(s) });
}

// ---------------------------------------------------------------- change password

const PasswordBody = z.object({ current: z.string().min(1).max(200), next: z.string().max(200) });

export async function changePassword(req: Request): Promise<Response> {
  const session = await requireSession(req);
  const body = PasswordBody.parse(await readJson(req));
  const [u] = await db().select().from(users).where(eq(users.id, session.userId)).limit(1);
  if (!u || !(await verifyPassword(body.current, u.passwordHash))) throw new ApiError(400, "Your current password is wrong.");
  const problem = passwordProblem(body.next);
  if (problem) throw new ApiError(400, problem);
  if (body.next === body.current) throw new ApiError(400, "Choose a new password that is different from the old one.");
  await db()
    .update(users)
    .set({ passwordHash: await hashPassword(body.next), mustChangePassword: false, updatedAt: new Date() })
    .where(eq(users.id, u.id));
  // Other phones signed in to this account must sign in again.
  await revokeAllSessions(u.id, session.sessionId);
  await audit(db(), u.id, "user", u.id, "password", `${u.name} changed their password`);
  const s = await activeSessionUser(session.sessionId);
  return json({ ok: true, user: s ? userJson(s) : null });
}
