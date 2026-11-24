/** Store accounts (owner only): add a rider/helper, turn an account off, give a new temporary password. */
import { eq, inArray } from "drizzle-orm";
import { z } from "zod";
import { users } from "../../../db/schema.js";
import { hashPassword, temporaryPassword } from "../auth/crypto.js";
import { requireOwner } from "../auth/guard.js";
import { requireSession } from "../auth/require-session.js";
import { findUserByPhone, revokeAllSessions } from "../auth/sessions.js";
import { audit } from "../audit.js";
import { db } from "../db.js";
import { ApiError, json, readJson, uuidParam } from "../http.js";
import { phoneField } from "./auth.js";

const userJson = (u: typeof users.$inferSelect) => ({ id: u.id, name: u.name, phone: u.phone, role: u.role, active: u.active });

export async function listUsers(req: Request): Promise<Response> {
  const s = await requireSession(req);
  requireOwner(s);
  const rows = await db().select().from(users).where(inArray(users.role, ["owner", "staff"])).orderBy(users.name);
  return json({ users: rows.map(userJson) });
}

const NewUser = z.object({
  name: z.string().trim().min(2, "Enter the name.").max(80),
  phone: phoneField,
  role: z.enum(["staff", "owner"]).default("staff"),
});

export async function addUser(req: Request): Promise<Response> {
  const s = await requireSession(req);
  requireOwner(s);
  const body = NewUser.parse(await readJson(req));
  if (await findUserByPhone(body.phone)) throw new ApiError(409, "That number already has an account.");
  const password = temporaryPassword();
  const d = db();
  const [u] = await d
    .insert(users)
    .values({ name: body.name, phone: body.phone, role: body.role, passwordHash: await hashPassword(password), mustChangePassword: true, createdBy: s.userId, device: "Phone" })
    .returning();
  await audit(d, s.userId, "user", u.id, "add", `${s.name} added ${body.role} account ${u.name}`);
  return json({ user: userJson(u), temporaryPassword: password }, { status: 201 });
}

const PatchUser = z.object({
  name: z.string().trim().min(2).max(80).optional(),
  active: z.boolean().optional(),
  resetPassword: z.boolean().optional(),
});

export async function updateUser(req: Request, params: Record<string, string>): Promise<Response> {
  const s = await requireSession(req);
  requireOwner(s);
  const id = uuidParam(params, "id", "That account");
  const body = PatchUser.parse(await readJson(req));
  const d = db();
  const [u] = await d.select().from(users).where(eq(users.id, id)).limit(1);
  if (!u || u.role === "customer") throw new ApiError(404, "That account was not found.");
  if (id === s.userId && body.active === false) throw new ApiError(400, "You cannot turn off your own account.");
  let password: string | null = null;
  const patch: Partial<typeof users.$inferInsert> = { updatedAt: new Date() };
  if (body.name !== undefined) patch.name = body.name;
  if (body.active !== undefined) patch.active = body.active;
  if (body.resetPassword) {
    password = temporaryPassword();
    patch.passwordHash = await hashPassword(password);
    patch.mustChangePassword = true;
  }
  const [row] = await d.update(users).set(patch).where(eq(users.id, id)).returning();
  if (body.active === false || body.resetPassword) await revokeAllSessions(id);
  await audit(d, s.userId, "user", id, "update", `${s.name} updated the account of ${row.name}${body.active === false ? " (turned off)" : ""}${password ? " (new password)" : ""}`);
  return json({ user: userJson(row), temporaryPassword: password });
}
