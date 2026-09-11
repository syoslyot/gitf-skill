#!/usr/bin/env bash
# gitf-survey.sh — the single FACTS source for /gitf.
# Emits ONE line of JSON: platform capabilities + branch/topology + worktrees,
# all read from the live git DAG and `git worktree list`. The skill reads this
# verbatim and never re-derives facts itself. Reads only the live git DAG —
# never a per-project config or any saved-state file.
#
# Re-run on every /gitf — never cached.
set -uo pipefail

GIT_DIR=$(git rev-parse --git-dir 2>/dev/null || true)

# jstr <val> -> JSON string, or bare null when val == "null".
jstr() { [ "$1" = "null" ] && printf 'null' || printf '"%s"' "$1"; }

emit() {
  printf '{"platform":{"provider":"%s","needs_login":%s,"has_remote":%s,"default_remote":%s},"branch":{"current":%s,"head":%s,"dirty":%s},"topology":{"model":%s,"integration":%s,"is_integration":%s,"is_develop":%s,"is_main":%s,"gitf_branch":%s,"ahead_of_integration":%s,"merged_into_integration":%s,"ahead_of_origin":%s,"develop_ahead_of_main":%s},"worktrees":{"current_path":%s,"main_path":%s,"current_is_linked":%s,"develop_at":%s,"main_at":%s}}\n' \
    "$PROVIDER" "$NEEDS_LOGIN" "$HAS_REMOTE" "$(jstr "$DEFAULT_REMOTE")" \
    "$(jstr "$CURRENT")" "$(jstr "$HEAD")" "$DIRTY" \
    "$(jstr "$MODEL")" "$(jstr "$INTEGRATION")" "$IS_INTEGRATION" "$IS_DEVELOP" "$IS_MAIN" "$(jstr "$GITF_BRANCH")" "$AHEAD_OF_INTEGRATION" "$MERGED_INTO_INTEGRATION" "$AHEAD_OF_ORIGIN" "$DEVELOP_AHEAD_OF_MAIN" \
    "$(jstr "$CURRENT_PATH")" "$(jstr "$MAIN_PATH")" "$CURRENT_IS_LINKED" "$(jstr "$DEVELOP_AT")" "$(jstr "$MAIN_AT")"
}

# Defaults (Tasks 2 & 3 fill branch/topology/worktrees).
PROVIDER=local; NEEDS_LOGIN=false; HAS_REMOTE=false; DEFAULT_REMOTE=null
CURRENT=null; HEAD=null; DIRTY=false
MODEL=unknown; INTEGRATION=null; IS_INTEGRATION=false
IS_DEVELOP=false; IS_MAIN=false; GITF_BRANCH=null
AHEAD_OF_INTEGRATION=0; MERGED_INTO_INTEGRATION=false; AHEAD_OF_ORIGIN=0; DEVELOP_AHEAD_OF_MAIN=0
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

# ===== branch + topology =====
CURRENT=$(git branch --show-current); [ -z "$CURRENT" ] && CURRENT=null
HEAD=$(git rev-parse --short HEAD 2>/dev/null || echo null)
[ -n "$(git status --porcelain 2>/dev/null)" ] && DIRTY=true

branch_exists() { git show-ref --verify --quiet "refs/heads/$1"; }
count() { git rev-list --count "$1" 2>/dev/null || echo 0; }

# resolve_ref <name> -> a ref rev-list can use: the local branch when it exists,
# otherwise a remote-tracking ref. A fresh `git clone` of a Git Flow repo checks
# out only the default branch, so `develop` exists solely as
# refs/remotes/origin/develop. A refs/heads-only test would call that repo
# single-trunk and land feature work straight onto main.
resolve_ref() {
  if git show-ref --verify --quiet "refs/heads/$1"; then printf '%s' "$1"; return 0; fi
  local r
  r=$(git for-each-ref --format='%(refname:short)' --count=1 "refs/remotes/*/$1" 2>/dev/null)
  [ -n "$r" ] && { printf '%s' "$r"; return 0; }
  return 1
}

# trunk_name -> the single-trunk repo's trunk. Not every repo calls it `main`;
# emitting "main" for a `master` repo would be a false fact that silently routes
# every topic branch to nothing-to-do.
trunk_name() {
  local b r
  for b in main master trunk; do
    resolve_ref "$b" >/dev/null 2>&1 && { printf '%s' "$b"; return 0; }
  done
  r=$(git symbolic-ref -q --short "refs/remotes/${DEFAULT_REMOTE:-origin}/HEAD" 2>/dev/null)
  [ -n "$r" ] && { printf '%s' "${r##*/}"; return 0; }
  return 1
}

# The integration branch is where topic work lands: `develop` under two-trunk Git
# Flow, the trunk itself when there is no develop. Everything below measures
# against it rather than a hardcoded `develop`. `model=unknown` means neither
# could be identified — routing must stop rather than guess.
INTEGRATION_REF=""
if INTEGRATION_REF=$(resolve_ref develop); then
  MODEL=gitflow; INTEGRATION=develop
elif TRUNK_NAME=$(trunk_name); then
  MODEL=trunk; INTEGRATION="$TRUNK_NAME"; INTEGRATION_REF=$(resolve_ref "$TRUNK_NAME")
else
  MODEL=unknown; INTEGRATION=null; INTEGRATION_REF=""
fi

[ "$CURRENT" = develop ] && IS_DEVELOP=true
[ "$CURRENT" = main ] && IS_MAIN=true
[ "$INTEGRATION" != null ] && [ "$CURRENT" = "$INTEGRATION" ] && IS_INTEGRATION=true

# `release/*` and `hotfix/*` only mean something under gitflow: they exist to
# move work between develop and main. A trunk repo has neither promotion nor a
# separate production line, so such a branch is an ordinary topic branch —
# routing it to Flow B/C would LAND onto a develop that does not exist.
if [ "$MODEL" = gitflow ]; then
  case "$CURRENT" in
    release/*) GITF_BRANCH=release ;;
    hotfix/*)  GITF_BRANCH=hotfix ;;
  esac
fi

if [ -n "$INTEGRATION_REF" ] && [ "$IS_INTEGRATION" = false ] && [ "$HEAD" != null ]; then
  AHEAD_OF_INTEGRATION=$(count "$INTEGRATION_REF..HEAD")
  git merge-base --is-ancestor HEAD "$INTEGRATION_REF" 2>/dev/null && MERGED_INTO_INTEGRATION=true
fi
if [ "$HEAD" != null ] && git rev-parse --verify -q '@{upstream}' >/dev/null 2>&1; then
  AHEAD_OF_ORIGIN=$(count '@{upstream}..HEAD')
fi
if D_REF=$(resolve_ref develop) && M_REF=$(resolve_ref main); then
  DEVELOP_AHEAD_OF_MAIN=$(count "$M_REF..$D_REF")
fi

# ===== worktrees =====
CURRENT_PATH=$(git rev-parse --show-toplevel 2>/dev/null || echo null)
wt_path=""; first=1
while IFS= read -r line; do
  case "$line" in
    "worktree "*)
      wt_path="${line#worktree }"
      if [ "$first" = 1 ]; then MAIN_PATH="$wt_path"; first=0; fi ;;
    "branch refs/heads/develop") DEVELOP_AT="$wt_path" ;;
    "branch refs/heads/main")    MAIN_AT="$wt_path" ;;
  esac
done < <(git worktree list --porcelain 2>/dev/null)
if [ "$CURRENT_PATH" != null ] && [ "$CURRENT_PATH" != "$MAIN_PATH" ]; then
  CURRENT_IS_LINKED=true
fi

emit
exit 0
