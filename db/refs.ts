import { sql } from "drizzle-orm";
import type { PgDatabase, PgQueryResultHKT } from "drizzle-orm/pg-core";

/** Human reference prefixes: O = app order, W = walk-in sale (POS), P = payment. */
export type RefPrefix = "O" | "W" | "P";

// eslint-disable-next-line @typescript-eslint/no-explicit-any -- any Drizzle Postgres db or transaction
type Tx = PgDatabase<PgQueryResultHKT, any>;

/**
 * Next gap-free ref ("O-0026"). The counter row is locked by the upsert until the transaction
 * ends, so two phones ordering at once never get the same number, and a rolled-back
 * transaction gives its number back.
 */
export async function nextRef(tx: Tx, prefix: RefPrefix): Promise<string> {
  const result = await tx.execute(sql`
    insert into ref_counters (prefix, next_value) values (${prefix}, 2)
    on conflict (prefix) do update set next_value = ref_counters.next_value + 1, updated_at = now()
    returning next_value - 1 as n`);
  const rows = (Array.isArray(result) ? result : (result as { rows: unknown[] }).rows) as { n: number | string }[];
  return formatRef(prefix, Number(rows[0].n));
}

export function formatRef(prefix: RefPrefix, n: number): string {
  return `${prefix}-${String(n).padStart(4, "0")}`;
}
