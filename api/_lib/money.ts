/** Money helpers (server). All amounts are integer centavos: ₱ 1.00 = 100. Mirrors app/lib/core/money.dart. */

export type Centavos = number;

const group = new Intl.NumberFormat("en-US", { maximumFractionDigits: 0 });

/** "₱ 1,050" (centavos only when not zero) or "₱ 1,050.00" with `always`. */
export function formatPeso(c: Centavos, opts: { always?: boolean } = {}): string {
  const sign = c < 0 ? "-" : "";
  const abs = Math.abs(Math.round(c));
  const whole = Math.floor(abs / 100);
  const frac = abs % 100;
  const showFrac = opts.always || frac !== 0;
  return `${sign}₱ ${group.format(whole)}${showFrac ? "." + String(frac).padStart(2, "0") : ""}`;
}
