import { auditLog } from "../../db/schema.js";
import type { Db } from "./db.js";

/** One line in the audit trail ("who did what"). Never put passwords or tokens in `after`. */
export async function audit(
  q: Db,
  actorId: string | null,
  entity: string,
  entityId: string | null,
  action: string,
  summary: string,
  extra: { before?: unknown; after?: unknown } = {},
) {
  await q.insert(auditLog).values({
    actorId,
    createdBy: actorId,
    device: "Phone",
    entity,
    entityId,
    action,
    summary,
    before: extra.before ?? null,
    after: extra.after ?? null,
  });
}
