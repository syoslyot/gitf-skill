#!/usr/bin/env bash
# test-survey.sh — capability + topology + worktree mock tests for gitf-survey.sh.
# Pure-local, no network. Exit 0 = green.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SURVEY="$SCRIPT_DIR/../gitf-survey.sh"
PASS=0; FAIL=0
SANDBOX="$(mktemp -d)"; trap 'rm -rf "$SANDBOX"' EXIT

# Clean bin with no gh, so "gh not installed" is real.
CLEAN_BIN="$SANDBOX/cleanbin"; mkdir -p "$CLEAN_BIN"
for t in git tr grep head cut sed cat bash env sort; do
  p="$(command -v "$t" 2>/dev/null)" && ln -sf "$p" "$CLEAN_BIN/$t"
done
# Fake gh: auth status exit driven by GH_FAKE_LOGGED_IN.
FAKE_BIN="$SANDBOX/fakebin"; mkdir -p "$FAKE_BIN"
cat > "$FAKE_BIN/gh" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "auth" ] && [ "${2:-}" = "status" ]; then
  [ "${GH_FAKE_LOGGED_IN:-false}" = "true" ] && exit 0 || exit 1
fi
exit 0
EOF
chmod +x "$FAKE_BIN/gh"

# field <json> <key> -> value (string|bool|null|int). Keys are unique in our JSON.
field() {
  echo "$1" | grep -oE "\"$2\":(\"[^\"]*\"|true|false|null|-?[0-9]+)" \
    | head -n1 | sed -E 's/.*:("?)([^"]*)\1/\2/'
}
check() { # check <desc> <json> <key> <want>
  local got; got="$(field "$2" "$3")"
  if [ "$got" = "$4" ]; then PASS=$((PASS+1)); else
    FAIL=$((FAIL+1)); echo "FAIL: $1 — $3 want '$4' got '$got'"; echo "  $2"; fi
}
new_repo() { # new_repo [--no-remote]
  local d; d="$(mktemp -d "$SANDBOX/repo.XXXXXX")"
  ( cd "$d" && git init -q -b main && git config user.email t@t && git config user.name t \
      && git commit -q --allow-empty -m c0 )
  [ "${1:-}" != "--no-remote" ] && ( cd "$d" && git remote add origin https://example.com/x.git )
  echo "$d"
}
run() { # run <repo> <gh_installed> <logged_in>
  local repo="$1" gh_on="$2" logged="$3" path
  [ "$gh_on" = true ] && path="$FAKE_BIN:$CLEAN_BIN" || path="$CLEAN_BIN"
  ( cd "$repo" && PATH="$path" GH_FAKE_LOGGED_IN="$logged" bash "$SURVEY" )
}

# --- platform matrix ---
R="$(new_repo)"; J="$(run "$R" true true)"
check "github provider"      "$J" provider github
check "github needs_login"   "$J" needs_login false
check "github has_remote"    "$J" has_remote true

R="$(new_repo)"; J="$(run "$R" true false)"
check "needs_login provider" "$J" provider local
check "needs_login flag"     "$J" needs_login true

R="$(new_repo)"; J="$(run "$R" false false)"
check "no-gh provider"       "$J" provider local
check "no-gh has_remote"     "$J" has_remote true

R="$(new_repo --no-remote)"; J="$(run "$R" true true)"
check "no-remote provider"        "$J" provider local
check "no-remote has_remote"      "$J" has_remote false
check "no-remote default_remote"  "$J" default_remote null

D="$(mktemp -d "$SANDBOX/plain.XXXXXX")"; J="$(run "$D" true true)"
check "non-git provider"    "$J" provider local
check "non-git has_remote"  "$J" has_remote false

echo "------------------------------------"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
