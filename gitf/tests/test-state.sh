#!/usr/bin/env bash
# test-state.sh — unit tests for gitf-state.sh. Pure-local, exit 0 = green.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE="$SCRIPT_DIR/../gitf-state.sh"
PASS=0; FAIL=0
SANDBOX="$(mktemp -d)"; trap 'rm -rf "$SANDBOX"' EXIT

# Each call points the store at a fresh temp file via GITF_STATE_FILE.
SF="$SANDBOX/state.json"
run() { GITF_STATE_FILE="$SF" bash "$STATE" "$@"; }

ok() { # ok <desc> <got> <want>
  if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else
    FAIL=$((FAIL+1)); echo "FAIL: $1 — got '$2' want '$3'"; fi
}

# 1. get on missing file → empty
rm -f "$SF"
ok "get missing → empty" "$(run get feature/x)" ""

# 2. put then get → roundtrip
run put feature/x '{"flow":"A","step":"awaiting_merge","pr_number":3}'
ok "get after put flow" "$(run get feature/x | python3 -c 'import sys,json;print(json.load(sys.stdin)["flow"])')" "A"

# 3. two branches independent
run put release/v1.0.0 '{"flow":"B","step":"awaiting_code_review"}'
ok "branch1 intact" "$(run get feature/x | python3 -c 'import sys,json;print(json.load(sys.stdin)["pr_number"])')" "3"
ok "branch2 stored"  "$(run get release/v1.0.0 | python3 -c 'import sys,json;print(json.load(sys.stdin)["flow"])')" "B"

# 4. list keys (sorted for determinism)
ok "list keys" "$(run list | python3 -c 'import sys,json;print(",".join(sorted(json.load(sys.stdin))))')" "feature/x,release/v1.0.0"

# 5. del removes one, leaves the other
run del feature/x
ok "deleted gone" "$(run get feature/x)" ""
ok "other remains" "$(run get release/v1.0.0 | python3 -c 'import sys,json;print(json.load(sys.stdin)["flow"])')" "B"

# 6. non-v2 file treated as empty (migration)
echo '{"flow":"A","step":"awaiting_merge"}' > "$SF"
ok "non-v2 → empty get" "$(run get release/v1.0.0)" ""

# 7. malformed JSON on put → non-zero exit, existing entries preserved
rm -f "$SF"
run put feature/keep '{"flow":"A"}'
run put feature/bad 'not json at all' 2>/dev/null
ok "bad-put → exit 1" "$?" "1"
ok "bad-put preserves prior" "$(run get feature/keep | python3 -c 'import sys,json;print(json.load(sys.stdin)["flow"])')" "A"
ok "bad-put wrote nothing" "$(run get feature/bad)" ""

# ============================================================
# valid: SHA-ancestor identity check (real temp repo)
# ============================================================
REPO="$(mktemp -d "$SANDBOX/repo.XXXXXX")"
(
  cd "$REPO" && git init -q && git config user.email t@t && git config user.name t
  git commit -q --allow-empty -m c1
  git checkout -q -b feature/y
  git commit -q --allow-empty -m c2
)
PAUSE_SHA="$(cd "$REPO" && git rev-parse feature/y)"
# advance the branch
( cd "$REPO" && git commit -q --allow-empty -m c3 )
# valid: pause_sha is ancestor of advanced branch → exit 0
( cd "$REPO" && GITF_STATE_FILE="$SF" bash "$STATE" valid feature/y "$PAUSE_SHA" ) \
  && ok "valid: ancestor → 0" "0" "0" || ok "valid: ancestor → 0" "1" "0"
# recreate the branch with unrelated history → pause_sha NOT ancestor → exit 1
(
  cd "$REPO" && git checkout -q --detach
  git branch -q -D feature/y
  git checkout -q -b feature/y master 2>/dev/null || git checkout -q -b feature/y main
)
( cd "$REPO" && GITF_STATE_FILE="$SF" bash "$STATE" valid feature/y "$PAUSE_SHA" ) \
  && ok "valid: recreated → 1" "0" "1" || ok "valid: recreated → 1" "1" "1"

echo "------------------------------------"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
