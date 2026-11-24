# Habhab LPG

Android app for **Habhab LPG Trading** — customers order gasul, track the rider on a map, pay
cash / GCash / utang and see their listahan; the store (owner + staff) gets an orders board with
a chime, delivery with live GPS, walk-in POS, utang ledger, GCash checks and reports.
**One APK** for both: what you see depends on the account.

- Live: https://habhab-lpg.vercel.app (download page + API). Vercel project `habhab-lpg`, region sin1.
- Database: Neon Postgres (Vercel Marketplace, free, sin1). Files: private Vercel Blob store `habhab-lpg-files`.
- Android only (Flutter, `app/`). No web app, no iOS.

```
api/router.ts      the one Vercel Function (/api/* → api/_lib/app.ts route table)
api/_lib/          auth (phone + password, JWT + rotating refresh), ledger, routes/*
db/                Drizzle schema + migrations, scripts (user:create, wipe-qa, seed-starter)
app/               Flutter Android app
web/               download page (static). The APK is copied here by apk:publish (not in git)
tools/             dev-server (PGlite), make-icons, apk-publish, qa/smoke.sh, qa/live-check.ts
tests/             vitest + PGlite API tests
```

## Money and utang
All money is integer centavos. One formula everywhere (`api/_lib/ledger.ts`):
`balance = opening_balance + Σ delivered orders − Σ confirmed payments`.
GCash from a customer stays *pending* until the store confirms it.

## Local development
```bash
npm install
npm test                       # API tests (in-memory Postgres)
npm run dev:local -- --seed --owner     # API on http://localhost:8787 (fake data, prints a test owner login)
cd app && flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8787/api   # emulator → local API
cd app && flutter analyze && flutter test
```

## Deploy (from this Mac, Vercel CLI)
```bash
vercel env pull .env.local     # DATABASE_URL, BLOB_READ_WRITE_TOKEN, AUTH_SECRET, CRON_SECRET
npm run db:migrate             # only when db/schema.ts changed (npm run db:generate first)
vercel deploy --prod
npm run qa:smoke               # 10 checks against the live site
```
Deploys are made with the CLI (the project is not connected to Git), because the APK in `web/`
is not in git.

## Release a new app version
1. Bump `version:` in `app/pubspec.yaml` (e.g. `1.0.1+2`).
2. `cd app && flutter build apk --release --target-platform android-arm,android-arm64`
   (signed with `~/Documents/habhab-keystore/` via `app/android/key.properties`; never commit either).
3. `npm run apk:publish` → copies the APK to `web/` and `~/Downloads/habhab-lpg/`, sets the live version
   (installed apps show "May bagong update!").
4. `vercel deploy --prod`, then `npm run qa:smoke`.

## Accounts
- Owner: Sir Habhab, 0997 804 9635 (made with `npm run user:create -- --name "Habhab" --phone 09978049635`;
  `--reset-password` gives a new temporary one).
- Staff/riders: added by the owner in the app (More → Staff & riders).
- Customers sign up in the app. No SMS check (no paid services), so utang is off until the owner allows it.

## Checks against the live server
`npx tsx tools/qa/live-check.ts` runs a full order/GCash/POS/utang flow with two QA accounts.
Pre-launch only, `npx tsx db/wipe-qa.ts --yes-pre-launch` removes all orders/customers it made
(it refuses once real customers exist).
