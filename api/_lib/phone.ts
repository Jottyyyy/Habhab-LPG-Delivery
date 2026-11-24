/**
 * Philippine mobile numbers. Everything is stored as "09XXXXXXXXX".
 * Accepts "0997 804 9635", "+63 997-804-9635", "639978049635", "9978049635".
 */
export function normalizePhone(raw: string): string | null {
  let d = raw.replace(/[\s\-().]/g, "");
  if (d.startsWith("+")) d = d.slice(1);
  if (!/^\d+$/.test(d)) return null;
  if (d.startsWith("63") && d.length === 12) d = "0" + d.slice(2);
  else if (d.startsWith("9") && d.length === 10) d = "0" + d;
  return /^09\d{9}$/.test(d) ? d : null;
}
