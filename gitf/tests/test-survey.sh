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

# --- topology helpers ---
# repo_flow -> repo with main(c0), develop branched from main.
repo_flow() {
  local d; d="$(mktemp -d "$SANDBOX/flow.XXXXXX")"
  ( cd "$d" && git init -q -b main && git config user.email t@t && git config user.name t
    git commit -q --allow-empty -m c0
    git checkout -q -b develop )
  echo "$d"
}
run_local() { ( cd "$1" && PATH="$CLEAN_BIN" bash "$SURVEY" ); }

# On a topic branch (non-prefixed name) with one commit ahead of develop.
R="$(repo_flow)"
( cd "$R" && git checkout -q -b issue-42 && git commit -q --allow-empty -m work )
J="$(run_local "$R")"
check "topic current"            "$J" current issue-42
check "topic is_develop"         "$J" is_develop false
check "topic gitf_branch"        "$J" gitf_branch null
check "topic ahead_of_develop"   "$J" ahead_of_develop 1
check "topic merged_into_develop" "$J" merged_into_develop false

# After --no-ff merge into develop, the same tip is an ancestor of develop.
( cd "$R" && git checkout -q develop && git merge -q --no-ff issue-42 -m "Merge issue-42" )
( cd "$R" && git checkout -q issue-42 )
J="$(run_local "$R")"
check "merged ahead_of_develop"    "$J" ahead_of_develop 0
check "merged merged_into_develop" "$J" merged_into_develop true

# On develop, ahead of main.
R="$(repo_flow)"
( cd "$R" && git commit -q --allow-empty -m feature-on-develop )
J="$(run_local "$R")"
check "develop is_develop"          "$J" is_develop true
check "develop develop_ahead_of_main" "$J" develop_ahead_of_main 1

# On a release branch -> gitf_branch=release.
R="$(repo_flow)"
( cd "$R" && git checkout -q -b release/v1.2.0 )
J="$(run_local "$R")"
check "release gitf_branch" "$J" gitf_branch release

# On a hotfix branch -> gitf_branch=hotfix.
R="$(repo_flow)"
( cd "$R" && git checkout -q main && git checkout -q -b hotfix/urgent )
J="$(run_local "$R")"
check "hotfix gitf_branch" "$J" gitf_branch hotfix

# Dirty working tree.
R="$(repo_flow)"
( cd "$R" && git checkout -q -b wip && echo x > f.txt )
J="$(run_local "$R")"
check "dirty true" "$J" dirty true

# --- worktree facts ---
# develop lives in the main worktree; a linked worktree holds a topic branch.
R="$(repo_flow)"
( cd "$R" && git commit -q --allow-empty -m c1 )   # give develop a commit
WT="$SANDBOX/wt.$$"
( cd "$R" && git worktree add -q -b issue-99 "$WT" develop )
MAIN_TL="$( cd "$R" && git rev-parse --show-toplevel )"
WT_TL="$( cd "$WT" && git rev-parse --show-toplevel )"

# Surveyed from inside the linked worktree:
J="$( cd "$WT" && PATH="$CLEAN_BIN" bash "$SURVEY" )"
check "wt current_is_linked"  "$J" current_is_linked true
check "wt current_path"       "$J" current_path "$WT_TL"
check "wt main_path"          "$J" main_path "$MAIN_TL"
check "wt develop_at"         "$J" develop_at "$MAIN_TL"

# Surveyed from the main worktree (develop): not linked.
J="$( cd "$R" && PATH="$CLEAN_BIN" bash "$SURVEY" )"
check "main current_is_linked" "$J" current_is_linked false

echo "------------------------------------"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
