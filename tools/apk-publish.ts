/**
 * Put a new APK on the download page and tell the apps an update is ready.
 *   npm run apk:publish -- app/build/app/outputs/flutter-apk/app-release.apk
 * 1. copies the APK to web/Habhab-LPG.apk (served at https://habhab-lpg.vercel.app/Habhab-LPG.apk;
 *    /download points there) and to ~/Downloads/habhab-lpg/Habhab-LPG.apk for sending by Messenger,
 * 2. writes the version (from app/pubspec.yaml) to the live database, so installed apps show
 *    "May bagong update" on their next start.
 * Then deploy: `vercel deploy --prod` (the APK is not in git; the CLI uploads it).
 */
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { eq } from "drizzle-orm";
import { connect } from "../db/connect.js";
import { settings } from "../db/schema.js";

async function main() {
  const src = process.argv[2] ?? "app/build/app/outputs/flutter-apk/app-release.apk";
  if (!fs.existsSync(src)) throw new Error(`APK not found: ${src}`);
  const version = /^version:\s*([0-9.]+)/m.exec(fs.readFileSync("app/pubspec.yaml", "utf8"))?.[1];
  if (!version) throw new Error("No version in app/pubspec.yaml");

  fs.copyFileSync(src, "web/Habhab-LPG.apk");
  const out = path.join(os.homedir(), "Downloads", "habhab-lpg");
  fs.mkdirSync(out, { recursive: true });
  fs.copyFileSync(src, path.join(out, "Habhab-LPG.apk"));
  const mb = (fs.statSync(src).size / 1_048_576).toFixed(1);

  const { db, close } = connect();
  const [row] = await db.select().from(settings).where(eq(settings.key, "main"));
  if (!row) await db.insert(settings).values({ key: "main", storePhone: "09978049635" });
  await db.update(settings).set({ apkUrl: "/Habhab-LPG.apk", apkVersion: version, updatedAt: new Date() }).where(eq(settings.key, "main"));
  await close();
  console.log(`APK ${version} (${mb} MB) → web/Habhab-LPG.apk and ${out}/Habhab-LPG.apk; live version set.`);
  console.log("Now run: vercel deploy --prod");
}

main().catch((e) => {
  console.error(e instanceof Error ? e.message : e);
  process.exit(1);
});
