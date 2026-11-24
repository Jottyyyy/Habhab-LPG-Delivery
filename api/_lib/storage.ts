/**
 * Private file storage: Vercel Blob (private store) in production; the local test server
 * swaps in an in-memory store so it never needs the real token.
 */
import { del, get, list, put } from "@vercel/blob";

export type Storage = {
  put(pathname: string, body: Buffer | string, contentType: string): Promise<{ pathname: string }>;
  get(pathname: string): Promise<{ stream: ReadableStream; contentType: string | null } | null>;
  list(prefix: string): Promise<{ pathname: string; url: string }[]>;
  del(urls: string[]): Promise<void>;
};

const blob: Storage = {
  async put(pathname, body, contentType) {
    const r = await put(pathname, body, { access: "private", contentType, addRandomSuffix: false });
    return { pathname: r.pathname };
  },
  async get(pathname) {
    const r = await get(pathname, { access: "private" });
    return r ? { stream: r.stream as ReadableStream, contentType: r.blob.contentType } : null;
  },
  async list(prefix) {
    const out: { pathname: string; url: string }[] = [];
    let cursor: string | undefined;
    do {
      const page = await list({ prefix, cursor });
      out.push(...page.blobs.map((b) => ({ pathname: b.pathname, url: b.url })));
      cursor = page.hasMore ? page.cursor : undefined;
    } while (cursor);
    return out;
  },
  async del(urls) {
    if (urls.length) await del(urls);
  },
};

let current: Storage = blob;
export const storage = (): Storage => current;
export function setStorage(next: Storage | null) {
  current = next ?? blob;
}

/** In-memory storage (local test server). */
export function memoryStorage(): Storage {
  const files = new Map<string, { bytes: Uint8Array; type: string }>();
  return {
    async put(pathname, body, contentType) {
      files.set(pathname, { bytes: typeof body === "string" ? new TextEncoder().encode(body) : new Uint8Array(body), type: contentType });
      return { pathname };
    },
    async get(pathname) {
      const f = files.get(pathname);
      return f ? { stream: new Response(new Blob([f.bytes as BlobPart])).body!, contentType: f.type } : null;
    },
    async list(prefix) {
      return [...files.keys()].filter((k) => k.startsWith(prefix)).map((k) => ({ pathname: k, url: `memory://${k}` }));
    },
    async del(urls) {
      for (const u of urls) files.delete(u.replace("memory://", ""));
    },
  };
}
