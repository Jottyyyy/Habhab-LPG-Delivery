import { ApiError } from "../http.js";
import { authenticate, type Auth } from "./guard.js";
import { activeSessionUser } from "./sessions.js";

export type SessionCtx = Auth & { name: string; phone: string };

/**
 * Signed-in check for routes that read or change business data: a valid access token AND a
 * session that is still active (not signed out elsewhere, account not turned off).
 * The role comes from the database, so a role change applies at once.
 */
export async function requireSession(req: Request): Promise<SessionCtx> {
  const auth = await authenticate(req);
  const s = await activeSessionUser(auth.sessionId);
  if (!s) throw new ApiError(401, "Please sign in again.", { code: "session_ended" });
  return { ...auth, role: s.role, name: s.name, phone: s.phone };
}
