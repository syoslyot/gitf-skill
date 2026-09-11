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
check "topic model"              "$J" model gitflow
check "topic integration"        "$J" integration develop
check "topic is_integration"     "$J" is_integration false
check "topic is_develop"         "$J" is_develop false
check "topic gitf_branch"        "$J" gitf_branch null
check "topic ahead_of_integration"   "$J" ahead_of_integration 1
check "topic merged_into_integration" "$J" merged_into_integration false

# After --no-ff merge into develop, the same tip is an ancestor of develop.
( cd "$R" && git checkout -q develop && git merge -q --no-ff issue-42 -m "Merge issue-42" )
( cd "$R" && git checkout -q issue-42 )
J="$(run_local "$R")"
check "merged ahead_of_integration"    "$J" ahead_of_integration 0
check "merged merged_into_integration" "$J" merged_into_integration true

# On develop, ahead of main.
R="$(repo_flow)"
( cd "$R" && git commit -q --allow-empty -m feature-on-develop )
J="$(run_local "$R")"
check "develop is_develop"          "$J" is_develop true
check "develop is_integration"      "$J" is_integration true
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

# --- trunk model (no develop branch) ---
# repo_trunk -> repo with main only. main IS the integration branch.
repo_trunk() {
  local d; d="$(mktemp -d "$SANDBOX/trunk.XXXXXX")"
  ( cd "$d" && git init -q -b main && git config user.email t@t && git config user.name t
    git commit -q --allow-empty -m c0 )
  echo "$d"
}

# On main in a trunk repo: it is the integration branch, not a branch to warn about.
R="$(repo_trunk)"
J="$(run_local "$R")"
check "trunk model"          "$J" model trunk
check "trunk integration"    "$J" integration main
check "trunk is_integration" "$J" is_integration true
check "trunk is_main"        "$J" is_main true
check "trunk is_develop"     "$J" is_develop false
check "trunk develop_at"     "$J" develop_at null

# Topic branch in a trunk repo measures against main, not a missing develop.
# This is the regression the whole model exists for: before it, ahead_of_develop
# was 0 here and every trunk repo routed to nothing-to-do.
R="$(repo_trunk)"
( cd "$R" && git checkout -q -b feature/thing && git commit -q --allow-empty -m work )
J="$(run_local "$R")"
check "trunk topic model"             "$J" model trunk
check "trunk topic is_integration"    "$J" is_integration false
check "trunk topic ahead_of_integration" "$J" ahead_of_integration 1
check "trunk topic merged_into_integration" "$J" merged_into_integration false

# After landing on main, the same tip is an ancestor -> cleanup-only re-run.
( cd "$R" && git checkout -q main && git merge -q --no-ff feature/thing -m "Merge feature/thing" )
( cd "$R" && git checkout -q feature/thing )
J="$(run_local "$R")"
check "trunk merged ahead_of_integration"    "$J" ahead_of_integration 0
check "trunk merged merged_into_integration" "$J" merged_into_integration true

# A trunk repo has no release line: develop_ahead_of_main stays 0.
check "trunk develop_ahead_of_main" "$J" develop_ahead_of_main 0

# --- regressions from the trunk-model review ---

# A fresh clone of a Git Flow repo has develop only as refs/remotes/origin/develop.
# A refs/heads-only check would call this trunk and land features onto main.
SRC="$(repo_flow)"
( cd "$SRC" && git commit -q --allow-empty -m c1 && git checkout -q main )
CLONE="$SANDBOX/clone.$$"
git clone -q "$SRC" "$CLONE" 2>/dev/null
J="$( cd "$CLONE" && PATH="$CLEAN_BIN" bash "$SURVEY" )"
check "clone model"       "$J" model gitflow
check "clone integration" "$J" integration develop

# A trunk named `master` must be reported as `master`, not a fabricated `main`.
repo_master() {
  local d; d="$(mktemp -d "$SANDBOX/master.XXXXXX")"
  ( cd "$d" && git init -q -b master && git config user.email t@t && git config user.name t
    git commit -q --allow-empty -m c0 )
  echo "$d"
}
R="$(repo_master)"
J="$(run_local "$R")"
check "master model"          "$J" model trunk
check "master integration"    "$J" integration master
check "master is_integration" "$J" is_integration true
R2="$R"
( cd "$R2" && git checkout -q -b feature/x && git commit -q --allow-empty -m w )
J="$(run_local "$R2")"
check "master topic ahead_of_integration" "$J" ahead_of_integration 1

# release/* in a trunk repo is an ordinary topic branch — routing it to Flow B
# would LAND onto a develop that does not exist.
R="$(repo_trunk)"
( cd "$R" && git checkout -q -b release/v1.0.0 )
J="$(run_local "$R")"
check "trunk release gitf_branch" "$J" gitf_branch null
R="$(repo_trunk)"
( cd "$R" && git checkout -q -b hotfix/urgent )
J="$(run_local "$R")"
check "trunk hotfix gitf_branch" "$J" gitf_branch null

# gitflow still classifies them.
R="$(repo_flow)"
( cd "$R" && git checkout -q -b release/v9.9.9 )
J="$(run_local "$R")"
check "gitflow release gitf_branch" "$J" gitf_branch release

# Neither develop nor a recognisable trunk -> unknown, never a guessed base.
D="$(mktemp -d "$SANDBOX/odd.XXXXXX")"
( cd "$D" && git init -q -b integration-line && git config user.email t@t && git config user.name t
  git commit -q --allow-empty -m c0 )
J="$(run_local "$D")"
check "unknown model"       "$J" model unknown
check "unknown integration" "$J" integration null

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
