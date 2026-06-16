#!/usr/bin/env bash
# gitf-detect.sh
# Capability-based platform detection for /gitf.
# Emits a single line of JSON describing the current repo's platform capabilities.
# The skill reads this output verbatim — it does NOT do any platform reasoning itself.
#
# Detection is about CAPABILITY, not remote-URL shape:
#   1. no remote                 -> local
#   2. gh installed AND logged-in -> github
#   3. gh installed, not logged-in -> local + needs_login=true
#   4. gh not installed          -> local
#
# A logged-in gh routes `gh pr create` to the correct host on its own, so
# GitHub Enterprise needs no special case. URL parsing would just re-solve a
# problem gh already solved.
#
# Re-run on every /gitf — never cached. Mid-session login / gh install /
# remote add is reflected on the next call.

set -uo pipefail

# --- Locate the git dir + worktree root (empty if not a repo) ---
GIT_DIR=$(git rev-parse --git-dir 2>/dev/null || true)
TOPLEVEL=$(git rev-parse --show-toplevel 2>/dev/null || true)

emit() {
  # $1=provider $2=needs_login $3=has_remote $4=default_remote
  # $5=gh_installed $6=gh_logged_in $7=platform_config
  local remote_field="null"
  [ "$4" != "null" ] && remote_field="\"$4\""
  printf '{"provider":"%s","needs_login":%s,"has_remote":%s,"default_remote":%s,"gh_installed":%s,"gh_logged_in":%s,"platform_config":"%s"}\n' \
    "$1" "$2" "$3" "$remote_field" "$5" "$6" "$7"
}

# --- Not a git repo: nothing to detect ---
if [ -z "$GIT_DIR" ]; then
  emit "local" "false" "false" "null" "false" "false" "auto"
  exit 0
fi

# --- Config override: .gitf/config {"platform":"auto|github|local",...} ---
PLATFORM_CONFIG="auto"
CONFIG_FILE="$TOPLEVEL/.gitf/config"
if [ -f "$CONFIG_FILE" ]; then
  # Tolerant parse: strip whitespace/CR, grab the platform value if valid.
  val=$(tr -d '[:space:]\r' < "$CONFIG_FILE" \
        | grep -oE '"platform":"(auto|github|local)"' \
        | head -n1 | cut -d'"' -f4 || true)
  [ -n "$val" ] && PLATFORM_CONFIG="$val"
fi

# --- Remote presence ---
DEFAULT_REMOTE="null"
HAS_REMOTE="false"
if git remote >/dev/null 2>&1 && [ -n "$(git remote)" ]; then
  HAS_REMOTE="true"
  if git remote | grep -qx "origin"; then
    DEFAULT_REMOTE="origin"
  else
    DEFAULT_REMOTE=$(git remote | head -n1)
  fi
fi

# --- gh capabilities ---
GH_INSTALLED="false"
GH_LOGGED_IN="false"
if command -v gh >/dev/null 2>&1; then
  GH_INSTALLED="true"
  # `gh auth status` is portable across gh versions (unlike `gh auth token --hostname`).
  if gh auth status >/dev/null 2>&1; then
    GH_LOGGED_IN="true"
  fi
fi

# --- Config override short-circuits capability logic ---
if [ "$PLATFORM_CONFIG" = "local" ]; then
  emit "local" "false" "$HAS_REMOTE" "$DEFAULT_REMOTE" "$GH_INSTALLED" "$GH_LOGGED_IN" "local"
  exit 0
fi
if [ "$PLATFORM_CONFIG" = "github" ]; then
  # Forced github: still report needs_login if gh isn't ready, so the skill can prompt.
  needs_login="false"
  [ "$GH_LOGGED_IN" = "false" ] && needs_login="true"
  emit "github" "$needs_login" "$HAS_REMOTE" "$DEFAULT_REMOTE" "$GH_INSTALLED" "$GH_LOGGED_IN" "github"
  exit 0
fi

# --- auto: capability decision tree ---
# 1. no remote -> local
if [ "$HAS_REMOTE" = "false" ]; then
  emit "local" "false" "false" "null" "$GH_INSTALLED" "$GH_LOGGED_IN" "auto"
  exit 0
fi
# 2. gh installed AND logged-in -> github
if [ "$GH_INSTALLED" = "true" ] && [ "$GH_LOGGED_IN" = "true" ]; then
  emit "github" "false" "true" "$DEFAULT_REMOTE" "true" "true" "auto"
  exit 0
fi
# 3. gh installed, not logged-in -> local + needs_login
if [ "$GH_INSTALLED" = "true" ]; then
  emit "local" "true" "true" "$DEFAULT_REMOTE" "true" "false" "auto"
  exit 0
fi
# 4. gh not installed -> local
emit "local" "false" "true" "$DEFAULT_REMOTE" "false" "false" "auto"
exit 0
