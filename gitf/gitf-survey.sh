#!/usr/bin/env bash
# gitf-survey.sh — the single FACTS source for /gitf.
# Emits ONE line of JSON: platform capabilities + branch/topology + worktrees,
# all read from the live git DAG and `git worktree list`. The skill reads this
# verbatim and never re-derives facts itself. No .gitf/config, no state file.
#
# Re-run on every /gitf — never cached.
set -uo pipefail

GIT_DIR=$(git rev-parse --git-dir 2>/dev/null || true)

# jstr <val> -> JSON string, or bare null when val == "null".
jstr() { [ "$1" = "null" ] && printf 'null' || printf '"%s"' "$1"; }

emit() {
  printf '{"platform":{"provider":"%s","needs_login":%s,"has_remote":%s,"default_remote":%s},"branch":{"current":%s,"head":%s,"dirty":%s},"topology":{"is_develop":%s,"is_main":%s,"gitf_branch":%s,"ahead_of_develop":%s,"merged_into_develop":%s,"ahead_of_origin":%s,"develop_ahead_of_main":%s},"worktrees":{"current_path":%s,"main_path":%s,"current_is_linked":%s,"develop_at":%s,"main_at":%s}}\n' \
    "$PROVIDER" "$NEEDS_LOGIN" "$HAS_REMOTE" "$(jstr "$DEFAULT_REMOTE")" \
    "$(jstr "$CURRENT")" "$(jstr "$HEAD")" "$DIRTY" \
    "$IS_DEVELOP" "$IS_MAIN" "$(jstr "$GITF_BRANCH")" "$AHEAD_OF_DEVELOP" "$MERGED_INTO_DEVELOP" "$AHEAD_OF_ORIGIN" "$DEVELOP_AHEAD_OF_MAIN" \
    "$(jstr "$CURRENT_PATH")" "$(jstr "$MAIN_PATH")" "$CURRENT_IS_LINKED" "$(jstr "$DEVELOP_AT")" "$(jstr "$MAIN_AT")"
}

# Defaults (Tasks 2 & 3 fill branch/topology/worktrees).
PROVIDER=local; NEEDS_LOGIN=false; HAS_REMOTE=false; DEFAULT_REMOTE=null
CURRENT=null; HEAD=null; DIRTY=false
IS_DEVELOP=false; IS_MAIN=false; GITF_BRANCH=null
AHEAD_OF_DEVELOP=0; MERGED_INTO_DEVELOP=false; AHEAD_OF_ORIGIN=0; DEVELOP_AHEAD_OF_MAIN=0
CURRENT_PATH=null; MAIN_PATH=null; CURRENT_IS_LINKED=false; DEVELOP_AT=null; MAIN_AT=null

# Not a git repo: emit minimal facts.
if [ -z "$GIT_DIR" ]; then emit; exit 0; fi

# ===== platform =====
if [ -n "$(git remote 2>/dev/null)" ]; then
  HAS_REMOTE=true
  if git remote | grep -qx origin; then DEFAULT_REMOTE=origin
  else DEFAULT_REMOTE=$(git remote | head -n1); fi
fi
GH_INSTALLED=false; GH_LOGGED_IN=false
if command -v gh >/dev/null 2>&1; then
  GH_INSTALLED=true
  gh auth status >/dev/null 2>&1 && GH_LOGGED_IN=true
fi
if [ "$HAS_REMOTE" = true ]; then
  if [ "$GH_INSTALLED" = true ] && [ "$GH_LOGGED_IN" = true ]; then
    PROVIDER=github
  elif [ "$GH_INSTALLED" = true ]; then
    NEEDS_LOGIN=true   # gh present but not logged in -> local + prompt
  fi
fi

emit
exit 0
