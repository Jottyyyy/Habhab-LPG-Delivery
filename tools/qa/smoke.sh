#!/usr/bin/env bash
# Production smoke test (read-only + public endpoints). Usage: npm run qa:smoke [-- https://habhab-lpg.vercel.app]
set -u
BASE="${1:-https://habhab-lpg.vercel.app}"
PASS=0; FAIL=0
check() { if [ "$2" = "$3" ]; then echo "PASS  $1"; PASS=$((PASS+1)); else echo "FAIL  $1 (got $2, want $3)"; FAIL=$((FAIL+1)); fi; }
code() { curl -s -o /dev/null -w "%{http_code}" "$@"; }
check "download page" "$(code "$BASE/")" 200
check "logo" "$(code "$BASE/logo.png")" 200
check "API + database" "$(curl -s "$BASE/api/status" | grep -c '"ok":true')" 1
check "app version" "$(code "$BASE/api/app/version")" 200
check "APK download link" "$(code "$BASE/download")" 307
check "APK file" "$(code -I "$BASE/Habhab-LPG.apk")" 200
check "store needs sign-in" "$(code "$BASE/api/store")" 401
check "orders need sign-in" "$(code "$BASE/api/seller/orders")" 401
check "wrong password refused" "$(code -X POST "$BASE/api/auth/login" -H 'content-type: application/json' -d '{"phone":"09000000000","password":"nope-nope"}')" 401
check "backup needs secret" "$(code "$BASE/api/cron/backup")" 401
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
