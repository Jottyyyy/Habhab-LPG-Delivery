/**
 * Make every icon and logo file from the client's logo (brand/habhab-logo.jpg).
 *   npm run icons
 * Writes:
 *   brand/icon-1024.png            launcher icon (navy, cream disc, flame "H")
 *   brand/icon-foreground.png      Android adaptive icon foreground (transparent)
 *   app/assets/brand/badge.png     the full round badge, background removed (sign-in, splash)
 *   app/assets/brand/flame.png     the flame "H" alone, background removed (headers)
 *   web/logo.png, web/favicon.png, web/icon-192.png   download page
 * Then run `dart run flutter_launcher_icons` in app/ for the Android launcher icons.
 */
import fs from "node:fs";
import sharp from "sharp";

const SRC = "brand/habhab-logo.jpg";
const NAVY = "#003F6A";
const CREAM = "#F6F4E7";
const GOLD = "#C1A363";

/** Make the background connected to the image edges transparent (flood fill by colour distance). */
async function removeEdgeBackground(input: Buffer, isBg: (r: number, g: number, b: number) => boolean): Promise<Buffer> {
  const { data, info } = await sharp(input).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  const w = info.width;
  const h = info.height;
  const seen = new Uint8Array(w * h);
  const stack: number[] = [];
  const push = (x: number, y: number) => {
    if (x < 0 || y < 0 || x >= w || y >= h) return;
    const i = y * w + x;
    if (seen[i]) return;
    const o = i * 4;
    if (!isBg(data[o], data[o + 1], data[o + 2])) return;
    seen[i] = 1;
    stack.push(i);
  };
  for (let x = 0; x < w; x++) {
    push(x, 0);
    push(x, h - 1);
  }
  for (let y = 0; y < h; y++) {
    push(0, y);
    push(w - 1, y);
  }
  while (stack.length) {
    const i = stack.pop()!;
    data[i * 4 + 3] = 0;
    const x = i % w;
    const y = (i - x) / w;
    push(x + 1, y);
    push(x - 1, y);
    push(x, y + 1);
    push(x, y - 1);
  }
  return sharp(data, { raw: { width: w, height: h, channels: 4 } }).png().toBuffer();
}

const nearWhite = (r: number, g: number, b: number) => r > 238 && g > 238 && b > 238;
const nearCream = (r: number, g: number, b: number) => r > 225 && g > 222 && b > 205 && Math.abs(r - g) < 14;

/** The flame "H" from the inner cream circle (gold ring painted over with cream first). */
async function flameOnCream(): Promise<Buffer> {
  const left = 790;
  const top = 596;
  const width = 350;
  const height = 584;
  const cover = (x: number, y: number, w: number, h: number) => ({
    input: { create: { width: w, height: h, channels: 4 as const, background: CREAM } },
    left: x - left,
    top: y - top,
  });
  return sharp(SRC)
    .extract({ left, top, width, height })
    .composite([cover(790, 596, 100, 60), cover(1040, 596, 100, 50)])
    .png()
    .toBuffer();
}

function discSvg(size: number, discRadius: number, opts: { background?: string }) {
  const c = size / 2;
  const ring = Math.round(discRadius * 0.045);
  return Buffer.from(
    `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}">` +
      (opts.background ? `<rect width="100%" height="100%" fill="${opts.background}"/>` : "") +
      `<circle cx="${c}" cy="${c}" r="${discRadius}" fill="${CREAM}" stroke="${GOLD}" stroke-width="${ring}"/>` +
      `</svg>`,
  );
}

async function iconWithFlame(size: number, discRadius: number, background?: string): Promise<Buffer> {
  const flame = await removeEdgeBackground(await flameOnCream(), nearCream);
  const flameH = Math.round(discRadius * 1.38);
  const resized = await sharp(flame).resize({ height: flameH }).toBuffer();
  const meta = await sharp(resized).metadata();
  return sharp(discSvg(size, discRadius, { background }))
    .composite([{ input: resized, left: Math.round((size - (meta.width ?? 0)) / 2), top: Math.round((size - flameH) / 2) - Math.round(discRadius * 0.02) }])
    .png()
    .toBuffer();
}

async function main() {
  fs.mkdirSync("app/assets/brand", { recursive: true });
  fs.mkdirSync("web", { recursive: true });

  // Launcher icon (legacy, full bleed) and adaptive foreground (inside the 66/108 safe zone).
  const icon = await iconWithFlame(1024, 430, NAVY);
  await sharp(icon).toFile("brand/icon-1024.png");
  await sharp(await iconWithFlame(1024, 300)).toFile("brand/icon-foreground.png");

  // Full badge with the white background removed.
  const badge = await removeEdgeBackground(fs.readFileSync(SRC), nearWhite);
  await sharp(badge).resize(720).png().toFile("app/assets/brand/badge.png");
  await sharp(badge).resize(512).png().toFile("web/logo.png");

  // The flame alone (transparent) for headers.
  const flame = await removeEdgeBackground(await flameOnCream(), nearCream);
  await sharp(flame).resize({ height: 240 }).png().toFile("app/assets/brand/flame.png");

  await sharp(icon).resize(192).png().toFile("web/icon-192.png");
  await sharp(icon).resize(64).png().toFile("web/favicon.png");
  console.log("Icons written. Next: cd app && dart run flutter_launcher_icons");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
