/**
 * The one Vercel Function behind /api/* (vercel.json rewrites every /api path here).
 * Routes live in api/_lib/app.ts; files under api/_lib are not deployed as functions.
 */
import { handle } from "./_lib/app.js";

export const GET = handle;
export const POST = handle;
export const PUT = handle;
export const PATCH = handle;
export const DELETE = handle;
export const OPTIONS = handle;
export const HEAD = handle;
