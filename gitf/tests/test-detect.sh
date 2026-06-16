#!/usr/bin/env bash
# test-detect.sh — capability-mock unit tests for gitf-detect.sh
#
# Detection is capability-based, so we mock only two facts:
#   - is gh installed?   (presence of a fake gh on PATH)
#   - is gh logged in?    (fake gh's `auth status` exit code, env-driven)
# There are NO remote-URL-shape cases — the detector never inspects host.
#
# Pure-local, no network. Exit 0 means all green.

set -uo pipefail

# Absolute path to the detector — must survive `cd` into sandbox subshells.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DETECT="$SCRIPT_DIR/../gitf-detect.sh"

PASS=0
FAIL=0
SANDBOX_ROOT="$(mktemp -d)"
trap 'rm -rf "$SANDBOX_ROOT"' EXIT

# --- Clean bin: symlinks to only the tools the detector uses, NO gh. ---
# Simulating "gh not installed" needs a PATH where gh genuinely cannot be found;
# stripping a dir from $PATH won't hide the real system gh.
CLEAN_BIN="$SANDBOX_ROOT/cleanbin"
mkdir -p "$CLEAN_BIN"
for t in git tr grep head cut sed cat bash env; do
  p="$(command -v "$t" 2>/dev/null)" && ln -sf "$p" "$CLEAN_BIN/$t"
done

# --- Fake gh: exit code of `auth status` driven by GH_FAKE_LOGGED_IN ---
# Env var name must NOT collide with the detector's internal GH_LOGGED_IN.
FAKE_BIN="$SANDBOX_ROOT/fakebin"
mkdir -p "$FAKE_BIN"
cat > "$FAKE_BIN/gh" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "auth" ] && [ "${2:-}" = "status" ]; then
  [ "${GH_FAKE_LOGGED_IN:-false}" = "true" ] && exit 0 || exit 1
fi
exit 0
EOF
chmod +x "$FAKE_BIN/gh"

# field <json> <key>  -> prints the value (handles string/bool/null)
field() {
  echo "$1" | grep -oE "\"$2\":(\"[^\"]*\"|true|false|null)" \
    | head -n1 | sed -E 's/.*:("?)([^"]*)\1/\2/'
}

# new_repo [--no-remote]  -> echoes a fresh repo dir
new_repo() {
  local d; d="$(mktemp -d "$SANDBOX_ROOT/repo.XXXXXX")"
  ( cd "$d" && git init -q && git config user.email t@t && git config user.name t )
  if [ "${1:-}" != "--no-remote" ]; then
    ( cd "$d" && git remote add origin https://example.com/x.git )
  fi
  echo "$d"
}

# run_detect <repo_dir> <gh_installed:true|false> <logged_in:true|false>
run_detect() {
  local repo="$1" gh_on="$2" logged="$3" path
  if [ "$gh_on" = "true" ]; then
    path="$FAKE_BIN:$CLEAN_BIN"   # fake gh present
  else
    path="$CLEAN_BIN"             # gh genuinely absent
  fi
  ( cd "$repo" && PATH="$path" GH_FAKE_LOGGED_IN="$logged" bash "$DETECT" )
}

check() {
  # check <desc> <json> <key> <expected>
  local desc="$1" json="$2" key="$3" want="$4" got
  got="$(field "$json" "$key")"
  if [ "$got" = "$want" ]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    echo "FAIL: $desc — $key expected '$want' got '$got'"
    echo "      json: $json"
  fi
}

# ============================================================
# Capability matrix
# ============================================================

# 1. remote + gh installed + logged in -> github
R="$(new_repo)"; J="$(run_detect "$R" true true)"
check "github: remote+gh+login provider" "$J" provider github
check "github: needs_login false"        "$J" needs_login false
check "github: has_remote true"          "$J" has_remote true
check "github: gh_logged_in true"        "$J" gh_logged_in true

# 2. remote + gh installed + NOT logged in -> local + needs_login
R="$(new_repo)"; J="$(run_detect "$R" true false)"
check "needs_login: provider local"  "$J" provider local
check "needs_login: needs_login true" "$J" needs_login true
check "needs_login: gh_installed true" "$J" gh_installed true
check "needs_login: gh_logged_in false" "$J" gh_logged_in false

# 3. remote + gh NOT installed -> local
R="$(new_repo)"; J="$(run_detect "$R" false false)"
check "no-gh: provider local"      "$J" provider local
check "no-gh: needs_login false"   "$J" needs_login false
check "no-gh: gh_installed false"  "$J" gh_installed false
check "no-gh: has_remote true"     "$J" has_remote true

# 4. NO remote -> local (regardless of gh)
R="$(new_repo --no-remote)"; J="$(run_detect "$R" true true)"
check "no-remote: provider local"   "$J" provider local
check "no-remote: has_remote false"  "$J" has_remote false
check "no-remote: default_remote null" "$J" default_remote null
check "no-remote: needs_login false" "$J" needs_login false

# ============================================================
# Config override
# ============================================================

# 5. platform:local forces local even with gh+login
R="$(new_repo)"; echo '{"platform":"local"}' > "$R/.git/gitf-config.json"
J="$(run_detect "$R" true true)"
check "override-local: provider"      "$J" provider local
check "override-local: platform_config" "$J" platform_config local
check "override-local: needs_login false" "$J" needs_login false

# 6. platform:github with gh not logged in -> github + needs_login
R="$(new_repo)"; echo '{"platform":"github"}' > "$R/.git/gitf-config.json"
J="$(run_detect "$R" true false)"
check "override-github: provider"      "$J" provider github
check "override-github: needs_login"   "$J" needs_login true

# 7. malformed config -> falls back to auto
R="$(new_repo)"; echo 'not json at all' > "$R/.git/gitf-config.json"
J="$(run_detect "$R" true true)"
check "malformed-config: provider github" "$J" provider github
check "malformed-config: platform_config auto" "$J" platform_config auto

# 8. CRLF + whitespace config still parses
R="$(new_repo)"; printf '  {\r\n  "platform" : "local"\r\n}\r\n' > "$R/.git/gitf-config.json"
J="$(run_detect "$R" true true)"
check "crlf-config: provider local" "$J" provider local

# 9. reserved/unknown platform value -> ignored, auto
R="$(new_repo)"; echo '{"platform":"gitlab"}' > "$R/.git/gitf-config.json"
J="$(run_detect "$R" true true)"
check "unknown-platform: platform_config auto" "$J" platform_config auto
check "unknown-platform: provider github" "$J" provider github

# ============================================================
# Mid-session changes (same repo, changing facts)
# ============================================================

# 10. gh logs in between calls
R="$(new_repo)"
J1="$(run_detect "$R" true false)"; check "midsession a: local before login" "$J1" provider local
J2="$(run_detect "$R" true true)";  check "midsession a: github after login" "$J2" provider github

# 11. gh gets installed between calls
R="$(new_repo)"
J1="$(run_detect "$R" false false)"; check "midsession b: local no gh" "$J1" gh_installed false
J2="$(run_detect "$R" true true)";   check "midsession b: github once installed" "$J2" provider github

# 12. remote added between calls
R="$(new_repo --no-remote)"
J1="$(run_detect "$R" true true)"; check "midsession c: local no remote" "$J1" has_remote false
( cd "$R" && git remote add origin https://example.com/y.git )
J2="$(run_detect "$R" true true)"; check "midsession c: github after remote add" "$J2" provider github

# 13. config flipped to local mid-session
R="$(new_repo)"
J1="$(run_detect "$R" true true)"; check "midsession d: github before override" "$J1" provider github
echo '{"platform":"local"}' > "$R/.git/gitf-config.json"
J2="$(run_detect "$R" true true)"; check "midsession d: local after override" "$J2" provider local

# ============================================================
# Non-git directory
# ============================================================

# 14. not a git repo -> local, no remote
D="$(mktemp -d "$SANDBOX_ROOT/plain.XXXXXX")"
J="$(run_detect "$D" true true)"
check "non-git: provider local"   "$J" provider local
check "non-git: has_remote false" "$J" has_remote false

# 15. non-origin remote -> default_remote is that remote
R="$(new_repo --no-remote)"; ( cd "$R" && git remote add upstream https://example.com/z.git )
J="$(run_detect "$R" true true)"
check "non-origin: default_remote upstream" "$J" default_remote upstream

# ============================================================
echo "------------------------------------"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
