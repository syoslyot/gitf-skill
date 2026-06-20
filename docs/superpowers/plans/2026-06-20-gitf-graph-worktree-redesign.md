# /gitf Graph-as-Source-of-Truth Worktree Redesign — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `/gitf` work under git worktrees and route by git topology instead of branch-name prefixes, while deleting the now-redundant `.gitf/config` and `.gitf/state.json`.

**Architecture:** A single facts script (`gitf-survey.sh`) emits one JSON of platform + branch/topology + worktree facts read from the live git DAG. `SKILL.md` routes from those facts. Worktree-awareness lives only in provider verb implementations; flows and the verb contract are unchanged. No persistent state: GitHub PR pauses and release positions are re-derived from `gh` + the graph each run.

**Tech Stack:** Bash (POSIX-ish, `set -uo pipefail`), git plumbing (`rev-list`, `merge-base`, `worktree list --porcelain`), `gh` CLI, Markdown skill files loaded on demand by Claude Code.

## Global Constraints

- Branch model is literal `develop` + `main`; topic branches may carry **any** name (no required prefix).
- gitf's own release/hotfix branches keep the `release/*` / `hotfix/*` shape — gitf both writes and reads these (closed loop, allowed).
- Merges are always merge commits (`--merge` / `--no-ff`); never squash/rebase.
- `[version only]` (i.e. `/gitf -v`): tag immediately after the release lands on main, before the back-merge to develop.
- Survey output is a single line of JSON read verbatim by the skill; the skill performs **no** platform/topology reasoning itself.
- Tests are pure-local, no network; `exit 0` = green. Follow the existing `tests/test-detect.sh` capability-mock pattern.
- `git worktree remove` is invoked **without** `--force`; its own refusal on a dirty tree is the guard.
- Commit messages: Conventional Commits subject; body = technical changes, blank line, then `問題：支援 worktree 並重新構想架構`. End with `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.

---

## File Structure

**Create:**
- `gitf/gitf-survey.sh` — the single FACTS script (supersedes `gitf-detect.sh`).
- `gitf/tests/test-survey.sh` — capability + topology + worktree mock tests.

**Modify:**
- `gitf/SKILL.md` — survey call, new decision tree, drop config/state bootstrap, add `--local` flag.
- `gitf/providers/local.md` — worktree-aware `LAND` and `CLEANUP`.
- `gitf/providers/github.md` — worktree-aware `CLEANUP`, gh-derived resume.
- `gitf/flows/flow-a.md` — stateless; gh-derived blocked handling.
- `gitf/flows/flow-b.md` — graph-positioned; stateless.
- `gitf/flows/flow-c.md` — graph-positioned; stateless.
- `gitf/flows/code-review-gate.md` — live reviewer detection; stateless pause.
- `gitf/flows/status-messages.md` — blocked messages drop state wording.
- `gitf/gitf-update.sh` — self-heal file list (drop state/detect, add survey).
- `gitf/.version` — bump.
- `evals/evals.json` — worktree + non-prefixed-branch + stateless-resume cases.

**Delete:**
- `gitf/gitf-state.sh`, `gitf/tests/test-state.sh`
- `gitf/gitf-detect.sh`, `gitf/tests/test-detect.sh`
- `gitf/INSTALL.md`
- `gitf/flows/resume.md`

---

## Task 1: Survey script — platform block + test harness

**Files:**
- Create: `gitf/gitf-survey.sh`
- Test: `gitf/tests/test-survey.sh`

**Interfaces:**
- Produces: `gitf-survey.sh` prints one JSON line. After this task the `platform` object is real; the other three objects (`branch`, `topology`, `worktrees`) are emitted with placeholder defaults and filled in Tasks 2–3.
- `platform`: `{"provider":"github|local","needs_login":bool,"has_remote":bool,"default_remote":"<name>|null"}`. Logic ported verbatim from `gitf-detect.sh` **minus** the `.gitf/config` override (deleted in this redesign).

- [ ] **Step 1: Write the failing test**

Create `gitf/tests/test-survey.sh`:

```bash
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash gitf/tests/test-survey.sh`
Expected: FAIL — `gitf-survey.sh` does not exist yet (`bash: .../gitf-survey.sh: No such file or directory`), non-zero exit.

- [ ] **Step 3: Write minimal implementation**

Create `gitf/gitf-survey.sh`:

```bash
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
```

`chmod +x gitf/gitf-survey.sh`.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash gitf/tests/test-survey.sh`
Expected: PASS — `PASS=13 FAIL=0`, exit 0.

- [ ] **Step 5: Commit**

```bash
chmod +x gitf/gitf-survey.sh gitf/tests/test-survey.sh
git add gitf/gitf-survey.sh gitf/tests/test-survey.sh
git commit -m "feat(gitf): add survey FACTS script (platform block)

- gitf-survey.sh emits one JSON line; platform block ported from
  gitf-detect.sh minus the .gitf/config override (removed in redesign)
- test-survey.sh capability matrix mirrors test-detect.sh

問題：支援 worktree 並重新構想架構

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: Survey script — branch + topology block

**Files:**
- Modify: `gitf/gitf-survey.sh` (insert topology computation before `emit`)
- Test: `gitf/tests/test-survey.sh` (append topology cases)

**Interfaces:**
- Consumes: `gitf-survey.sh` from Task 1.
- Produces: `branch` = `{current, head, dirty}` and `topology` = `{is_develop, is_main, gitf_branch, ahead_of_develop, merged_into_develop, ahead_of_origin, develop_ahead_of_main}` all populated from git. `merged_into_develop` is true iff HEAD is an ancestor of `develop` (covers a topic branch already `--no-ff`-merged). `gitf_branch` is `release` / `hotfix` / null by gitf's own prefix.

- [ ] **Step 1: Write the failing test**

Append to `gitf/tests/test-survey.sh`, immediately before the final `echo "----"` block:

```bash
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash gitf/tests/test-survey.sh`
Expected: FAIL — e.g. `topic current — current want 'issue-42' got 'null'`, because topology is still the Task-1 default.

- [ ] **Step 3: Write minimal implementation**

In `gitf/gitf-survey.sh`, insert this block between the platform section and the final `emit` (after the `fi` closing the `HAS_REMOTE` platform block):

```bash
# ===== branch + topology =====
CURRENT=$(git branch --show-current); [ -z "$CURRENT" ] && CURRENT=null
HEAD=$(git rev-parse --short HEAD 2>/dev/null || echo null)
[ -n "$(git status --porcelain 2>/dev/null)" ] && DIRTY=true

branch_exists() { git show-ref --verify --quiet "refs/heads/$1"; }
count() { git rev-list --count "$1" 2>/dev/null || echo 0; }

[ "$CURRENT" = develop ] && IS_DEVELOP=true
[ "$CURRENT" = main ] && IS_MAIN=true
case "$CURRENT" in
  release/*) GITF_BRANCH=release ;;
  hotfix/*)  GITF_BRANCH=hotfix ;;
esac

if branch_exists develop && [ "$IS_DEVELOP" = false ] && [ "$HEAD" != null ]; then
  AHEAD_OF_DEVELOP=$(count "develop..HEAD")
  git merge-base --is-ancestor HEAD develop 2>/dev/null && MERGED_INTO_DEVELOP=true
fi
if [ "$HEAD" != null ] && git rev-parse --verify -q '@{upstream}' >/dev/null 2>&1; then
  AHEAD_OF_ORIGIN=$(count '@{upstream}..HEAD')
fi
if branch_exists develop && branch_exists main; then
  DEVELOP_AHEAD_OF_MAIN=$(count "main..develop")
fi
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash gitf/tests/test-survey.sh`
Expected: PASS — `FAIL=0`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add gitf/gitf-survey.sh gitf/tests/test-survey.sh
git commit -m "feat(gitf): survey branch + topology facts

- current/head/dirty + is_develop/is_main/gitf_branch
- ahead_of_develop, merged_into_develop (HEAD ancestor of develop),
  ahead_of_origin, develop_ahead_of_main — all from the git DAG

問題：支援 worktree 並重新構想架構

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: Survey script — worktrees block

**Files:**
- Modify: `gitf/gitf-survey.sh` (insert worktree parsing before `emit`)
- Test: `gitf/tests/test-survey.sh` (append worktree cases)

**Interfaces:**
- Consumes: `gitf-survey.sh` from Task 2.
- Produces: `worktrees` = `{current_path, main_path, current_is_linked, develop_at, main_at}`. `main_path` is the first entry of `git worktree list --porcelain` (the main worktree). `current_is_linked` is true when the current toplevel differs from `main_path`. `develop_at` / `main_at` are the worktree paths where `develop` / `main` are checked out, or null.

- [ ] **Step 1: Write the failing test**

Append to `gitf/tests/test-survey.sh`, before the final summary block:

```bash
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash gitf/tests/test-survey.sh`
Expected: FAIL — `wt current_is_linked — want 'true' got 'false'` (worktree block still default).

- [ ] **Step 3: Write minimal implementation**

In `gitf/gitf-survey.sh`, insert before the final `emit`:

```bash
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash gitf/tests/test-survey.sh`
Expected: PASS — `FAIL=0`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add gitf/gitf-survey.sh gitf/tests/test-survey.sh
git commit -m "feat(gitf): survey worktree topology facts

- parse git worktree list --porcelain: main_path, current_path,
  current_is_linked, develop_at, main_at

問題：支援 worktree 並重新構想架構

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: Rewire SKILL.md — survey call, topology routing, drop config/state

**Files:**
- Modify: `gitf/SKILL.md`

**Interfaces:**
- Consumes: `gitf-survey.sh` JSON (Tasks 1–3).
- Produces: the routing contract the flows rely on (which flow loads for which facts), and the `--local` / `-v` / `--skip-review` flag semantics.

- [ ] **Step 1: Replace bootstrap (Step -1) to drop the config check**

In `gitf/SKILL.md`, in "Step -1: Bootstrap / self-heal", **delete** the entire `.gitf/config` check block (the `[ -f .gitf/config ] || echo "GITF_NOT_CONFIGURED"` paragraph and its follow-up about loading `INSTALL.md`). Keep the `gitf-update.sh` run and the `flows/`+`providers/` self-heal `ls` check. Replace the self-heal `ls` line so it no longer mentions removed files:

```bash
ls ~/.claude/skills/gitf/flows/ ~/.claude/skills/gitf/providers/ \
   ~/.claude/skills/gitf/gitf-survey.sh >/dev/null 2>&1 || echo "GITF_NEEDS_HEAL"
```

- [ ] **Step 2: Replace Step 0 (detection) with the survey call**

Replace the whole "Step 0: Detect platform capabilities" section body with:

````markdown
## Step 0: Gather facts (single source of truth)

```bash
bash ~/.claude/skills/gitf/gitf-survey.sh
```

Read the JSON verbatim — do **not** re-derive any fact yourself.

```json
{"platform":{"provider":"github|local","needs_login":bool,"has_remote":bool,"default_remote":"origin|null"},
 "branch":{"current":"<name>","head":"<sha>","dirty":bool},
 "topology":{"is_develop":bool,"is_main":bool,"gitf_branch":"release|hotfix|null",
   "ahead_of_develop":int,"merged_into_develop":bool,"ahead_of_origin":int,"develop_ahead_of_main":int},
 "worktrees":{"current_path":"<abs>","main_path":"<abs>","current_is_linked":bool,
   "develop_at":"<abs|null>","main_at":"<abs|null>"}}
```

- `platform.needs_login=true` → emit **status-messages: needs-login** and stop
  (gh installed but not logged in; the user logs in, or passes `/gitf --local`).
- `platform.provider` selects which `providers/<provider>.md` you load once a flow
  is chosen. `/gitf --local` forces `provider=local` for this run regardless of
  the surveyed provider.
````

- [ ] **Step 3: Replace Step 0.5 (flags + saved state) with flags only**

Replace the "Step 0.5" section body with:

````markdown
## Step 0.5: Parse flags

- `/gitf -v` → `VERSION_MODE=true`; `/gitf` → `VERSION_MODE=false`. `-v` only
  affects Flow B/C tagging.
- `/gitf --skip-review` → `SKIP_REVIEW=true`; skips the code-review gate (B-4 /
  C-2) for this run only.
- `/gitf --local` → force the `local` provider for this run (override a GitHub
  remote). Replaces the old `.gitf/config` `platform:"local"` setting.

There is no saved state to consult: every pause point (a blocked GitHub PR, an
unfinished release, an unresolved review) is re-derived from `gh` and the git
graph by the chosen flow. Flows run idempotently — they probe before each action.
````

- [ ] **Step 4: Replace the Decision Tree with topology routing**

Replace the entire "Decision Tree → which flow to load" section with:

````markdown
## Decision Tree → which flow to load (routes from FACTS)

```
topology.is_main                              → status-messages: warn-on-main

topology.is_develop:
  branch.dirty || topology.ahead_of_origin>0  → flows/flow-d.md → flow-a
  topology.develop_ahead_of_main>0            → flows/flow-b.md  (full release)
  else                                        → status-messages: nothing-to-do

topology.gitf_branch == "release"             → flows/flow-b.md  (continue release)
topology.gitf_branch == "hotfix"              → flows/flow-c.md

else  (TOPIC branch — any name; not develop/main/release/hotfix):
  topology.ahead_of_develop>0                 → flows/flow-a.md
  topology.merged_into_develop
    && (branch still exists || worktree present) → flows/flow-a.md (CLEANUP only)
  else                                        → status-messages: nothing-to-do
```

**Routing**: load `flows/<chosen>.md` and `providers/<provider>.md`. Additionally
load `flows/status-messages.md` to emit a message, and `flows/code-review-gate.md`
when Flow B/C reaches B-4 / C-2. Load nothing else. Topic branches are classified
by topology, never by name prefix.
````

- [ ] **Step 5: Delete the State file schema section and update Rules**

Delete the entire "## State file schema (v2)" section. In "## Rules":
- Delete the bullets referencing `gitf-state.sh`, `.gitf/state.json`, `pause_sha`, and "Drop a branch's state entry".
- Replace the in-flight ordering bullet with:
  `**In-flight ordering**: starting a release (B-0) halts if any unfinished release/* or hotfix/* exists; a hotfix (C-0) halts only on another unfinished hotfix/*. Derived from git branches, not stored state.`
- Replace the code-review bullet's tail so it reads: `The reviewer tools are detected live (see code-review-gate.md); judge their output — do not hardcode an "empty == pass" rule.`
- Keep all other rules. Update the "Step 0.5 cache hit?" mention anywhere to remove it.

- [ ] **Step 6: Verify SKILL.md has no dangling references**

Run:
```bash
grep -nE 'gitf-state|state\.json|pause_sha|GITF_NOT_CONFIGURED|INSTALL\.md|resume\.md|gitf-detect|cache hit' gitf/SKILL.md
```
Expected: **no output** (exit 1). If any line prints, fix that reference.

- [ ] **Step 7: Commit**

```bash
git add gitf/SKILL.md
git commit -m "refactor(gitf): route from survey topology, drop config/state

- Step 0 now calls gitf-survey.sh; routing reads topology facts, no prefixes
- topic branches classified by ahead_of_develop/merged_into_develop
- remove .gitf/config bootstrap, state schema, cache-hit/resume path
- add /gitf --local flag (replaces config platform override)

問題：支援 worktree 並重新構想架構

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: Provider local — worktree-aware LAND and CLEANUP

**Files:**
- Modify: `gitf/providers/local.md`

**Interfaces:**
- Consumes: survey `worktrees.develop_at`, `worktrees.main_path`, `platform.default_remote`.
- Produces: `LAND` / `CLEANUP` behaviour that never runs `git checkout develop` in the current worktree when develop is checked out elsewhere.

- [ ] **Step 1: Rewrite the `LAND` section**

Replace the `## LAND base head [keep-branch]` section body with:

````markdown
**Idempotency probe (cache-miss runs only).** If `git log <base>..<head>` is empty,
`<head>` is already merged into `<base>` — skip the merge, go to the next step.

The merge must happen in the worktree that holds `<base>`. Use survey facts:

- If `<base>` is `develop` and `worktrees.develop_at` is non-null → run the merge
  in that path (it may be the current worktree or another one):

  ```bash
  git -C <develop_at> merge --no-ff <head> -m "Merge <head> into <base>"
  ```

- If `<base>` is not checked out in any worktree (its `*_at` is null) → create an
  ephemeral worktree, merge there, then remove it:

  ```bash
  tmp=$(mktemp -d)
  git worktree add "$tmp" <base>
  git -C "$tmp" merge --no-ff <head> -m "Merge <head> into <base>"
  git worktree remove "$tmp"
  ```

If `has_remote=true`, push the base afterward: `git push <remote> <base>`.

`keep-branch` only affects later CLEANUP; the merge itself is unchanged. Never
blocks — proceed straight to the next flow step.
````

- [ ] **Step 2: Rewrite the `CLEANUP` section (worktree-aware)**

Replace the `## CLEANUP branch` section body with:

````markdown
Delete the branch and, if it lives in a worktree, remove that worktree first.
Never stand in the worktree being removed.

```bash
# 1. If <branch> is checked out in a worktree, remove it (no --force: a dirty
#    tree makes git refuse, which is our intended halt — report and stop).
wt=$(git worktree list --porcelain | awk -v b="refs/heads/<branch>" '
  /^worktree /{p=$2} $0=="branch "b{print p}')
if [ -n "$wt" ]; then
  git -C "$(git rev-parse --show-toplevel)" rev-parse >/dev/null 2>&1
  cd <main_path>            # leave the worktree before removing it
  git worktree remove "$wt" || { echo "GITF_HALT: worktree $wt not clean"; exit 0; }
fi

# 2. Delete the branch (now unblocked) locally + remotely.
git branch -d <branch> 2>/dev/null || true
# has_remote=true:
git push <remote> --delete <branch> 2>/dev/null || true

# 3. Hygiene.
git worktree prune
```

If `git worktree remove` printed `GITF_HALT`, stop the flow and tell the user the
worktree has uncommitted/untracked changes and must be cleaned or removed by hand.
````

- [ ] **Step 3: Remove the trailing state-del line**

Delete the `bash ~/.claude/skills/gitf/gitf-state.sh del "<branch>"` line and its "Hygiene: drop this branch's state entry" comment from the old CLEANUP (now replaced). Confirm:

```bash
grep -n 'gitf-state' gitf/providers/local.md
```
Expected: no output.

- [ ] **Step 4: Commit**

```bash
git add gitf/providers/local.md
git commit -m "refactor(gitf): worktree-aware local LAND and CLEANUP

- LAND merges inside develop's own worktree (survey develop_at), or an
  ephemeral worktree when develop is unchecked out — never checkout develop
- CLEANUP removes the branch's worktree (no --force; git refusal = halt)
  before branch -d, then prune; drop the state-del line

問題：支援 worktree 並重新構想架構

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 6: Provider github — worktree-aware CLEANUP, gh-derived resume

**Files:**
- Modify: `gitf/providers/github.md`

**Interfaces:**
- Consumes: survey `worktrees.*`; `gh pr` queries.
- Produces: `CLEANUP` that is worktree-safe; a documented "re-locate the PR via `gh pr list`" idiom replacing state-based resume.

- [ ] **Step 1: Rewrite the `CLEANUP` section (worktree-aware)**

Replace the `## CLEANUP branch` section body with:

````markdown
```bash
git push origin --delete <branch> 2>/dev/null || true

# Remove the branch's worktree first if it has one (no --force: dirty => halt).
wt=$(git worktree list --porcelain | awk -v b="refs/heads/<branch>" '
  /^worktree /{p=$2} $0=="branch "b{print p}')
if [ -n "$wt" ]; then
  cd <main_path>
  git worktree remove "$wt" || { echo "GITF_HALT: worktree $wt not clean"; exit 0; }
fi

git branch -d <branch> 2>/dev/null || true
git worktree prune
```

If `GITF_HALT` printed, stop and tell the user the worktree is not clean.
````

- [ ] **Step 2: Add the gh-derived resume note to `LAND`**

At the end of the `## LAND` section, replace the paragraph beginning "When blocked, report the blocking `mergeStateStatus`..." with:

````markdown
When blocked, report the blocking `mergeStateStatus` and the PR number to the
flow, emit the matching `blocked-*` status message, and stop. **No state is
written.** On the next `/gitf`, the flow re-locates this PR with
`gh pr list --head <head> --base <base> --state all --json number,state,mergeStateStatus`
and continues from the graph: an `OPEN` PR is re-checked, a `MERGED` PR advances
to the next step, a `CLOSED`-unmerged PR is treated as a fresh start.
````

- [ ] **Step 3: Verify no state references remain**

```bash
grep -n 'gitf-state\|state.json\|pause_sha' gitf/providers/github.md
```
Expected: no output.

- [ ] **Step 4: Commit**

```bash
git add gitf/providers/github.md
git commit -m "refactor(gitf): worktree-aware github CLEANUP, gh-derived resume

- CLEANUP removes the branch's worktree (no --force) before branch -d
- blocked PRs write no state; next run re-locates via gh pr list

問題：支援 worktree 並重新構想架構

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 7: Flow A — stateless, gh-derived

**Files:**
- Modify: `gitf/flows/flow-a.md`

**Interfaces:**
- Consumes: provider `LAND` / `SYNC` / `CLEANUP`; survey `topology.merged_into_develop`.
- Produces: a stateless Flow A that also handles the "merged-but-not-cleaned" re-run.

- [ ] **Step 1: Replace the github blocked/state paragraph**

In `gitf/flows/flow-a.md`, delete the `**github provider**: if LAND reports the PR blocked, save the entry ...` paragraph **and** the entire ```bash gitf-state.sh put ...``` block. Replace with:

```markdown
**github provider**: if `LAND` reports the PR blocked, emit the matching
`blocked-*` message and stop. No state is written — the next `/gitf` re-locates
the PR via `gh pr list --head <current-branch>` (see providers/github.md) and
continues.
```

- [ ] **Step 2: Replace step 2 (drop state del) and add the cleanup-only entry**

Replace the numbered step "2. On success → ..." with:

```markdown
2. On success → `SYNC develop` → `CLEANUP <current-branch>` (github deletes the
   PR branch on merge; still call CLEANUP to remove any worktree and local ref) →
   **status-messages: flow-a-done**

**Cleanup-only re-run**: if routed here with `topology.merged_into_develop=true`
and the branch/worktree still present (the prior run merged but could not finish
cleanup, e.g. a leaked worktree), skip `LAND` and run `CLEANUP <current-branch>`
directly, then **status-messages: flow-a-done**.
```

- [ ] **Step 3: Verify**

```bash
grep -n 'gitf-state\|pause_sha' gitf/flows/flow-a.md
```
Expected: no output.

- [ ] **Step 4: Commit**

```bash
git add gitf/flows/flow-a.md
git commit -m "refactor(gitf): stateless Flow A with cleanup-only re-run

- drop state writes; blocked PRs re-located via gh next run
- merged_into_develop + branch/worktree present => CLEANUP-only path

問題：支援 worktree 並重新構想架構

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 8: Flows B and C — graph-positioned, stateless

**Files:**
- Modify: `gitf/flows/flow-b.md`, `gitf/flows/flow-c.md`

**Interfaces:**
- Consumes: provider verbs; `gh pr list` for resume; survey topology; git tag/branch existence for idempotency.
- Produces: release/hotfix flows that re-derive their position from the graph and `gh`, with no state writes.

- [ ] **Step 1: Flow B — replace version_mode resume note**

In `gitf/flows/flow-b.md`, replace the paragraph "**Resuming on an existing release/* branch via cache-miss** ..." with:

```markdown
**Resuming on an existing `release/*` branch**: there is no saved `-v` flag, so
infer `version_mode`/`version` from the branch name — `release/v<X.Y.Z>` →
`version_mode=true, version=<X.Y.Z>`; `release/<YYYY-MM-DD>` → `version_mode=false`.
To resume **and** tag a date-named release, the user re-runs `/gitf -v`. Position
within the flow is derived from the graph + `gh` (see B-5/B-7 below), not state.
```

- [ ] **Step 2: Flow B — replace B-5 github blocked block**

Replace the B-5 github bullet (`- github: if blocked, save the entry ...` and its ```bash``` state block) with:

```markdown
- github: if blocked, emit the matching `blocked-*` message and stop. No state.
  Next `/gitf` on this `release/*` branch re-locates the release→main PR via
  `gh pr list --head <release-branch> --base main --state all` — `MERGED` advances
  to B-6/B-7, `OPEN` is re-checked, `CLOSED`-unmerged restarts B-5.
- local: synchronous merge into main, push main if `has_remote`.
```

- [ ] **Step 3: Flow B — replace B-7 github blocked block**

Replace the B-7 github bullet and its ```bash``` state block with:

```markdown
- github: create the back-merge PR with `--head <release-branch>` (current branch
  may be `main`). If blocked, emit `blocked-*` and stop. No state. Next `/gitf`
  re-locates the release→develop PR via
  `gh pr list --head <release-branch> --base develop --state all` and resumes:
  `MERGED` → B-8, `OPEN` → re-check, `CLOSED`-unmerged → recreate.
- local: synchronous merge into develop, push if `has_remote`.
```

- [ ] **Step 4: Flow B — fix B-8 cleanup wording**

Replace the B-8 line so it reads:

```markdown
### B-8: Cleanup

`CLEANUP <release-branch>` → `SYNC develop` → **status-messages: flow-b-done**.
(CLEANUP removes any worktree for the release branch; see the provider.)
```

- [ ] **Step 5: Flow B — make B-2 worktree-safe**

In B-2, replace the `git checkout develop && git pull` / `git checkout -b` snippet's resume guard so it does not assume a single worktree:

```markdown
Idempotency: if `<release-branch>` already exists, just ensure you are on it
(`git checkout <release-branch>` in the current worktree); do not recreate it and
do not `git checkout develop`. Fresh release from develop: `SYNC develop` then
`git checkout -b <release-branch>` from develop's tip.
```

- [ ] **Step 6: Flow C — replace C-3 and C-5 github blocked blocks**

In `gitf/flows/flow-c.md`, replace the C-3 github bullet + its state ```bash``` block with:

```markdown
- github: if blocked, emit `blocked-*` and stop. No state. Next `/gitf` on this
  `hotfix/*` branch re-locates the hotfix→main PR via
  `gh pr list --head <hotfix-branch> --base main --state all` and resumes.
- local: synchronous merge into main, push if `has_remote`.
```

Replace the C-5 github bullet + its state ```bash``` block with:

```markdown
- github: create the back-merge PR with `--head <hotfix-branch>`. If blocked,
  emit `blocked-*` and stop. No state. Next `/gitf` re-locates the
  hotfix→develop PR via `gh pr list --head <hotfix-branch> --base develop
  --state all` and resumes.
- local: synchronous merge into develop, push if `has_remote`.
```

- [ ] **Step 7: Flow C — fix C-6 cleanup wording**

Replace the C-6 line so it reads:

```markdown
### C-6: Cleanup

`CLEANUP <hotfix-branch>` → `SYNC develop` → **status-messages: flow-c-done**.
```

- [ ] **Step 8: Verify both flows are stateless**

```bash
grep -nE 'gitf-state|pause_sha|state\.json' gitf/flows/flow-b.md gitf/flows/flow-c.md
```
Expected: no output.

- [ ] **Step 9: Commit**

```bash
git add gitf/flows/flow-b.md gitf/flows/flow-c.md
git commit -m "refactor(gitf): graph-positioned, stateless Flow B and C

- blocked PRs write no state; resume re-locates via gh pr list + graph
- version_mode inferred from release branch name or re-passed -v
- cleanup wording notes worktree removal

問題：支援 worktree 並重新構想架構

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 9: Code-review gate + status-messages — live reviewers, stateless pause; delete resume.md

**Files:**
- Modify: `gitf/flows/code-review-gate.md`, `gitf/flows/status-messages.md`
- Delete: `gitf/flows/resume.md`

**Interfaces:**
- Consumes: the session's installed review skills (detected live).
- Produces: a gate that detects reviewers at runtime (no `.gitf/config`) and pauses without writing state.

- [ ] **Step 1: Rewrite gate Inputs and reviewer detection**

In `gitf/flows/code-review-gate.md`, replace the `- .gitf/config → reviewers:` input line with:

```markdown
- Reviewers — detected live this run, in preference order, keeping those that
  exist: (1) `code-review` skill/plugin, (2) `superpowers:requesting-code-review`,
  (3) `review` skill. `ls ~/.claude/skills/ 2>/dev/null` plus the session's
  visible skill list. Use the single highest-preference one by default.
```

Replace the `Read reviewers from .gitf/config. IF reviewers is empty / missing → skip` lines in the Procedure with:

```markdown
Detect reviewers (above). IF none are available → skip the gate, continue.
```

- [ ] **Step 2: Replace the gate's blocked-pause block (drop state)**

Replace the `IF blocking findings needing the user ...` branch — including its ```bash``` `gitf-state.sh put` block — with:

```markdown
  IF blocking findings needing the user (can't fix / design decision):
    Emit status-messages: blocked-code-review listing the remaining findings, and
    STOP. No state is written. On the next `/gitf`, routing lands back on this
    release/* (or hotfix/*) branch and re-enters this gate from the top
    (idempotent): resolved findings pass, unresolved ones stop again.
```

- [ ] **Step 3: Rewrite the gate's Resume section**

Replace the `## Resume` section with:

```markdown
## Resume

There is no saved state. Re-running `/gitf` on a release/* or hotfix/* branch that
has not yet landed on `main` re-enters this gate from the top and re-runs every
reviewer. Only once the gate passes does the flow proceed to landing on `main`.
```

- [ ] **Step 4: Update status-messages.md**

In `gitf/flows/status-messages.md`, find any `blocked-*` message text that mentions saved state / "resume from state" / `.gitf/state.json` and reword to "re-run `/gitf` to continue — state is re-derived from git". Then verify:

```bash
grep -nE 'state\.json|gitf-state|pause_sha|INSTALL' gitf/flows/status-messages.md
```
Expected: no output.

- [ ] **Step 5: Delete resume.md**

```bash
git rm gitf/flows/resume.md
```

- [ ] **Step 6: Verify nothing references resume.md**

```bash
grep -rn 'resume\.md' gitf/
```
Expected: no output.

- [ ] **Step 7: Commit**

```bash
git add gitf/flows/code-review-gate.md gitf/flows/status-messages.md
git commit -m "refactor(gitf): live reviewer detection, stateless gate, drop resume.md

- reviewers detected at runtime (no .gitf/config)
- review pause writes no state; re-run re-enters the gate idempotently
- delete flows/resume.md (routing now derives position from facts)

問題：支援 worktree 並重新構想架構

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 10: Remove dead files, update self-heal + version, final sweep

**Files:**
- Delete: `gitf/gitf-state.sh`, `gitf/tests/test-state.sh`, `gitf/gitf-detect.sh`, `gitf/tests/test-detect.sh`, `gitf/INSTALL.md`
- Modify: `gitf/gitf-update.sh`, `gitf/.version`

**Interfaces:**
- Consumes: nothing new.
- Produces: a tree with a single facts script and no state/config machinery.

- [ ] **Step 1: Delete superseded files**

```bash
git rm gitf/gitf-state.sh gitf/tests/test-state.sh \
       gitf/gitf-detect.sh gitf/tests/test-detect.sh gitf/INSTALL.md
```

- [ ] **Step 2: Update gitf-update.sh self-heal file list**

Open `gitf/gitf-update.sh`. If it enumerates expected files or verifies specific paths (e.g. a list including `gitf-detect.sh`, `gitf-state.sh`, `INSTALL.md`, `flows/resume.md`), update that list to drop those four and add `gitf-survey.sh`. If it only syncs the whole `gitf/` tree via tarball with no per-file list, leave the sync logic and only adjust any post-sync `ls` verification to reference `gitf-survey.sh` instead of `gitf-detect.sh`. Verify:

```bash
grep -nE 'gitf-detect|gitf-state|INSTALL|resume\.md' gitf/gitf-update.sh
```
Expected: no output.

- [ ] **Step 3: Bump version**

Read `gitf/.version` (e.g. `1.0.1`) and write the next minor (e.g. `1.1.0`) — this is a feature release.

```bash
printf '1.1.0\n' > gitf/.version
```

- [ ] **Step 4: Repo-wide reference sweep**

```bash
grep -rnE 'gitf-detect|gitf-state|state\.json|pause_sha|INSTALL\.md|resume\.md|GITF_NOT_CONFIGURED|\.gitf/config' gitf/
```
Expected: **no output**. Any hit is a dangling reference — fix it before committing.

- [ ] **Step 5: Run the survey tests once more**

Run: `bash gitf/tests/test-survey.sh`
Expected: `FAIL=0`, exit 0.

- [ ] **Step 6: Commit**

```bash
git add -A gitf/
git commit -m "chore(gitf): remove state/config machinery, bump to v1.1.0

- delete gitf-state.sh, gitf-detect.sh, their tests, and INSTALL.md
- update gitf-update.sh self-heal to expect gitf-survey.sh
- bump .version 1.0.1 -> 1.1.0

問題：支援 worktree 並重新構想架構

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 11: Update evals

**Files:**
- Modify: `evals/evals.json`

**Interfaces:**
- Consumes: the redesigned skill behaviour.
- Produces: eval cases covering worktrees, non-prefixed branches, and stateless resume.

- [ ] **Step 1: Inspect the current eval shape**

Run: `cat evals/evals.json` (note the JSON schema each case uses — fields like `name`, `setup`, `prompt`, `expect`).

- [ ] **Step 2: Add cases matching that schema**

Add (using the existing field names) at least these cases:
1. **non-prefixed topic branch → Flow A**: setup a repo on branch `issue-42` with a commit ahead of develop; prompt `/gitf`; expect it lands `issue-42` into develop and cleans up (no "unknown branch" / no-op).
2. **topic branch in a linked worktree → Flow A + worktree removed**: setup a worktree on `feat-x`; prompt `/gitf`; expect merge to develop then `git worktree remove` of that worktree and branch deletion.
3. **dirty worktree halts cleanup**: worktree with an untracked file after merge; expect the run to stop and report the unclean worktree rather than force-removing.
4. **stateless resume**: a `release/v1.2.0` branch already merged to main but not back-merged (no `.gitf/state.json`); prompt `/gitf`; expect it derives position from the graph and performs the develop back-merge + cleanup.

- [ ] **Step 3: Validate JSON**

Run: `python3 -c 'import json;json.load(open("evals/evals.json"))'`
Expected: no output, exit 0 (valid JSON).

- [ ] **Step 4: Commit**

```bash
git add evals/evals.json
git commit -m "test(gitf): eval cases for worktree + non-prefixed-branch + stateless resume

問題：支援 worktree 並重新構想架構

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage** (each §6/§7/§8 spec item → task):
- Survey FACTS interface (spec §4①) → Tasks 1–3.
- Topology routing, no prefixes (spec §5) → Task 4 Step 4.
- Eliminate `.gitf/config` + INSTALL ceremony (spec §6) → Task 4 Steps 1–3, Task 9 Step 1, Task 10 Step 1.
- Eliminate `.gitf/state.json` (spec §6) → Tasks 4–9 (state writes removed everywhere) + Task 10 Step 1.
- Worktree CLEANUP order + dirty-halt via git's own refusal (spec §7) → Tasks 5–6.
- local LAND when develop is in another worktree (spec §7) → Task 5 Step 1.
- gh-derived resume replacing bookmarks (spec §6) → Tasks 6–9.
- Live reviewer detection (spec §8 gate) → Task 9 Step 1.
- Testing: survey tests + evals (spec §10) → Tasks 1–3, 11.
- Migration: delete state/config/INSTALL, ignore old `.gitf/` (spec §11) → Task 10.

**Placeholder scan:** every code step shows complete bash; markdown edits give exact replacement text; verification steps give exact `grep` commands with expected empty output. No TBD/TODO.

**Type/name consistency:** JSON keys are identical across the survey script (`emit` printf), the SKILL.md schema block (Task 4 Step 2), and the routing tree (Task 4 Step 4): `is_develop`, `is_main`, `gitf_branch`, `ahead_of_develop`, `merged_into_develop`, `ahead_of_origin`, `develop_ahead_of_main`, `current_is_linked`, `develop_at`, `main_at`. The `GITF_HALT` sentinel is emitted and checked consistently in Tasks 5–6. Verb names (`LAND`/`PUBLISH`/`SYNC`/`TAG`/`CLEANUP`) are unchanged from the existing contract.
