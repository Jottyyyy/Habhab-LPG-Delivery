/** Public: newest APK version (update banner in the app) and the download link for the website. */
import { db } from "../db.js";
import { json } from "../http.js";
import { getSettings } from "../store-settings.js";

export async function appVersion(_req: Request): Promise<Response> {
  const st = await getSettings(db());
  return json({ latestVersion: st.apkVersion, minVersion: st.minAppVersion, downloadUrl: st.apkUrl ? "/download" : null });
}

export async function appDownload(_req: Request): Promise<Response> {
  const st = await getSettings(db());
  if (!st.apkUrl) {
    return new Response("The app is not uploaded yet. Please ask the store.", { status: 404, headers: { "Content-Type": "text/plain; charset=utf-8" } });
  }
  return new Response(null, { status: 302, headers: { Location: st.apkUrl, "Cache-Control": "no-store" } });
}
