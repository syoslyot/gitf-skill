# Multi-Branch State Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let `/gitf` track per-branch flow state in a branch-keyed map, resume by current branch with SHA-fingerprint validation, and rebuild progress idempotently from git/gh reality on cache miss.

**Architecture:** Introduce `gitf-state.sh` — a tested state-access layer over a single `.gitf/state.json` (v2: `{"version":2,"flows":{"<branch>":{...}}}`). SKILL.md Step 0.5 becomes a cache lookup: hit (entry exists AND `pause_sha` is an ancestor of the current branch) → trust and resume; miss → run the decision tree with flows in idempotent mode (probe git/gh before each action, halt on ambiguity).

**Tech Stack:** bash + python3 (JSON surgery), git, gh. Tests are pure-local bash mirroring `gitf/tests/test-detect.sh`.

Spec: `docs/plans/2026-06-17-multibranch-state-design.md`.

---

## File structure

| File | Responsibility |
|------|----------------|
| `gitf/gitf-state.sh` (NEW) | State access layer: `get`/`put`/`del`/`list`/`valid` on one `.gitf/state.json` |
| `gitf/tests/test-state.sh` (NEW) | Unit tests for `gitf-state.sh` (pure-local) |
| `gitf/SKILL.md` | v2 schema; Step 0.5 cache hit/miss lookup; halt-on-ambiguity rule |
| `gitf/flows/resume.md` | Resume the entry for the current branch |
| `gitf/flows/flow-a.md` `flow-b.md` `flow-c.md` | Pauses write keyed entry + `pause_sha`; cache-miss idempotent probes; orphan-branch halt (B/C) |
| `gitf/flows/code-review-gate.md` | Write entry keyed by branch |
| `gitf/providers/github.md` | LAND probes "PR already exists?"; GC entry on CLEANUP |
| `gitf/providers/local.md` | LAND probes "already merged?"; GC entry on CLEANUP |
| `gitf/providers/README.md`, `spec/flows.md`, `spec/decision-tree.md`, `docs/usage.md` | Document the map, cache semantics, idempotency, halt principle |

---

## Task 1: `gitf-state.sh` — get/put/del/list

**Files:**
- Create: `gitf/gitf-state.sh`
- Create (test): `gitf/tests/test-state.sh`

- [ ] **Step 1: Write the failing test**

Create `gitf/tests/test-state.sh`:

```bash
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

echo "------------------------------------"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash gitf/tests/test-state.sh`
Expected: FAIL — `gitf/gitf-state.sh` does not exist (bash: cannot open file), non-zero exit.

- [ ] **Step 3: Write minimal implementation**

Create `gitf/gitf-state.sh`:

```bash
#!/usr/bin/env bash
# gitf-state.sh — state access layer for /gitf multi-branch state.
# Store: <worktree-root>/.gitf/state.json, schema v2:
#   {"version":2,"flows":{"<branch>":{...entry...}}}
# Subcommands act on one branch entry at a time. A missing or non-v2 file is
# treated as empty (no entries) — this is the v1→v2 migration path.
set -uo pipefail

TOPLEVEL=$(git rev-parse --show-toplevel 2>/dev/null || true)
STATE_FILE="${GITF_STATE_FILE:-$TOPLEVEL/.gitf/state.json}"

py() {
  GITF_STATE_FILE="$STATE_FILE" python3 - "$@" <<'PYEOF'
import json, sys, os
path = os.environ["GITF_STATE_FILE"]
def load():
    try:
        with open(path) as f:
            d = json.load(f)
        if isinstance(d, dict) and d.get("version") == 2 and isinstance(d.get("flows"), dict):
            return d
    except (FileNotFoundError, json.JSONDecodeError):
        pass
    return {"version": 2, "flows": {}}
def save(d):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(d, f, indent=2)
cmd = sys.argv[1]
d = load()
if cmd == "get":
    e = d["flows"].get(sys.argv[2])
    if e is not None:
        print(json.dumps(e))
elif cmd == "put":
    d["flows"][sys.argv[2]] = json.loads(sys.argv[3])
    save(d)
elif cmd == "del":
    d["flows"].pop(sys.argv[2], None)
    save(d)
elif cmd == "list":
    print(json.dumps(list(d["flows"].keys())))
PYEOF
}

cmd="${1:-}"; shift || true
case "$cmd" in
  get)  py get "$1" ;;
  put)  py put "$1" "$2" ;;
  del)  py del "$1" ;;
  list) py list ;;
  valid)
    # valid <branch> <sha> → exit 0 if sha is an ancestor of branch, else 1
    git merge-base --is-ancestor "$2" "$1" 2>/dev/null ;;
  *)
    echo "usage: gitf-state.sh {get <branch>|put <branch> <json>|del <branch>|list|valid <branch> <sha>}" >&2
    exit 2 ;;
esac
```

- [ ] **Step 4: Run test to verify it passes**

Run: `chmod +x gitf/gitf-state.sh && bash gitf/tests/test-state.sh`
Expected: `PASS=8 FAIL=0`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add gitf/gitf-state.sh gitf/tests/test-state.sh
git commit -m "feat(gitf): add gitf-state.sh state-access layer (get/put/del/list)

問題：我要支援多分支（state.json 只能存一個分支的狀態）

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: `gitf-state.sh valid` — SHA fingerprint check

**Files:**
- Modify (test): `gitf/tests/test-state.sh`
- (impl already added in Task 1; this task proves it with a real repo)

- [ ] **Step 1: Write the failing test**

Append to `gitf/tests/test-state.sh` **before** the final `echo "---"` summary block:

```bash
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
```

Note the default branch name: `git init` may produce `master` or `main`. The recreate line tries `master` then `main`. If your git defaults differ, the fallback covers both.

- [ ] **Step 2: Run test to verify it fails**

Temporarily break `valid` to confirm the new assertions are real: in `gitf/gitf-state.sh`, change the `valid)` line to `git merge-base --is-ancestor "$1" "$2"` (args swapped).
Run: `bash gitf/tests/test-state.sh`
Expected: FAIL on `valid: ancestor → 0` (swapped args invert the check).

- [ ] **Step 3: Restore the correct implementation**

Revert the `valid)` line back to:

```bash
    git merge-base --is-ancestor "$2" "$1" 2>/dev/null ;;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash gitf/tests/test-state.sh`
Expected: `PASS=10 FAIL=0`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add gitf/tests/test-state.sh
git commit -m "test(gitf): cover gitf-state.sh valid SHA-ancestor check

問題：我要支援多分支（撞名重用造成假命中）

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: SKILL.md — v2 schema + Step 0.5 cache lookup

**Files:**
- Modify: `gitf/SKILL.md`

- [ ] **Step 1: Replace the state schema section**

Find the `## State file schema` section. Replace its intro and table to describe v2 + `pause_sha`:

```markdown
## State file schema (v2)

`.gitf/state.json` is a branch-keyed map. Each paused flow is one entry; flows on
different branches are independent. Read/write it **only** via `gitf-state.sh`
(get/put/del/list/valid) — never hand-edit the JSON.

```json
{
  "version": 2,
  "flows": {
    "feature/auth-jwt": {
      "flow": "A", "step": "awaiting_merge", "pr_number": 3,
      "source_branch": "feature/auth-jwt", "target_branch": "develop",
      "pause_sha": "a1b2c3d"
    }
  }
}
```

Each entry's fields are unchanged from before, plus `pause_sha` — the
`git rev-parse <branch>` tip captured when the flow paused, used to detect a
reused branch name (see Step 0.5).
```

Keep the existing per-field table; add one row:

```markdown
| `pause_sha` | branch tip at pause time; resume trusts the entry only if this is an ancestor of the current branch |
```

- [ ] **Step 2: Rewrite Step 0.5 state lookup**

Replace the "check saved state" portion of Step 0.5 with the cache lookup:

```markdown
State lookup (cache hit / miss):

```bash
current=$(git branch --show-current)
entry=$(bash ~/.claude/skills/gitf/gitf-state.sh get "$current")
```

- **`entry` non-empty** → read its `pause_sha` and validate identity:

  ```bash
  bash ~/.claude/skills/gitf/gitf-state.sh valid "$current" "<pause_sha>"
  ```

  - exit 0 → **CACHE HIT**: load `flows/resume.md` and resume this entry. Do not
    re-derive anything from git/gh beyond what resume needs.
  - exit 1 → reused branch name; treat as **CACHE MISS**.

- **`entry` empty** → **CACHE MISS**: run detection from Step 1; the chosen flow
  executes in idempotent mode (probe git/gh before each action; see each flow).
```

- [ ] **Step 3: Add the halt-on-ambiguity rule**

In the `## Rules` section, add:

```markdown
- **Ambiguity halts.** On any ambiguous or unexpected state — a merge conflict,
  an orphaned `release/*`/`hotfix/*` branch, or contradictory probe results —
  stop and report to the user. Never guess or auto-recover.
- State lives in `.gitf/state.json` (v2 map) accessed only via `gitf-state.sh`.
  A paused flow's entry is keyed by its owning branch and carries `pause_sha`.
```

- [ ] **Step 4: Verify consistency**

Run: `grep -n 'pause_sha\|gitf-state.sh\|CACHE' gitf/SKILL.md`
Expected: schema row, Step 0.5 hit/miss block, and rules all present and mutually consistent.

- [ ] **Step 5: Commit**

```bash
git add gitf/SKILL.md
git commit -m "feat(gitf): v2 branch-keyed state schema + Step 0.5 cache lookup

問題：我要支援多分支（依當前分支 resume，命中信任、未命中重新推導）

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: resume.md — resume the current branch's entry

**Files:**
- Modify: `gitf/flows/resume.md`

- [ ] **Step 1: Update the resume entry-point**

Replace the opening of `gitf/flows/resume.md` (the part that reads state) with:

```markdown
# Flow Resume

Reached on a **cache hit** (Step 0.5): the current branch has a valid entry.

```bash
current=$(git branch --show-current)
entry=$(bash ~/.claude/skills/gitf/gitf-state.sh get "$current")
```

Read `flow` and `step` from `entry`, then branch on `step`:

- `step=awaiting_code_review` → re-enter the code-review gate
  (`flows/code-review-gate.md`) on `current`. If it passes, continue the owning
  flow: Flow B from B-5, Flow C from C-3. If it stops again, leave the entry and
  halt. No PR is involved.
- any other `step` → PR-merge pause (github); check the waiting PR below.
```

- [ ] **Step 2: Update state delete calls**

In `gitf/flows/resume.md`, replace every "delete state" / "delete `.gitf/state.json`" instruction with the keyed delete:

```bash
bash ~/.claude/skills/gitf/gitf-state.sh del "$current"
```

- [ ] **Step 3: Verify**

Run: `grep -n 'gitf-state.sh\|del ' gitf/flows/resume.md`
Expected: get at top, `del "$current"` at each completion point; no bare `.gitf/state.json` file deletes remain.

- [ ] **Step 4: Commit**

```bash
git add gitf/flows/resume.md
git commit -m "feat(gitf): resume the current branch's state entry

問題：我要支援多分支（依當前分支 resume）

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: Pauses write keyed entry + pause_sha

**Files:**
- Modify: `gitf/flows/flow-a.md`, `gitf/flows/flow-b.md`, `gitf/flows/flow-c.md`, `gitf/flows/code-review-gate.md`

- [ ] **Step 1: Define the shared "save entry" snippet in code-review-gate.md**

In `gitf/flows/code-review-gate.md`, replace the save instruction with:

```markdown
  IF blocking findings needing the user:
    Capture the pause point:
    ```bash
    pause_sha=$(git rev-parse "$current")
    bash ~/.claude/skills/gitf/gitf-state.sh put "$current" \
      '{"flow":"<B|C>","step":"awaiting_code_review","release_branch":"'"$current"'","version":<...>,"version_mode":<...>,"pause_sha":"'"$pause_sha"'"}'
    ```
    Emit status-messages: blocked-code-review and STOP.
```

- [ ] **Step 2: Update flow-a.md pause**

In `gitf/flows/flow-a.md`, replace the github "save state" instruction with:

```markdown
**github provider**: if `LAND` reports the PR blocked, save the entry keyed by
the current branch:

```bash
pause_sha=$(git rev-parse "$(git branch --show-current)")
bash ~/.claude/skills/gitf/gitf-state.sh put "$(git branch --show-current)" \
  '{"flow":"A","step":"awaiting_merge","pr_number":<n>,"source_branch":"<branch>","target_branch":"develop","pause_sha":"'"$pause_sha"'"}'
```

Then emit the `blocked-*` message and stop; the next `/gitf` resumes via `resume.md`.
```

- [ ] **Step 3: Update flow-b.md and flow-c.md pause writes**

In `gitf/flows/flow-b.md` (B-5 / B-7) and `gitf/flows/flow-c.md` (C-3 / C-5), each "save state" / "update state" instruction becomes a `gitf-state.sh put` keyed by `release_branch` (the release/hotfix branch you are on), always including `"pause_sha"` from `git rev-parse <release_branch>`. Example for B-5:

```bash
pause_sha=$(git rev-parse "<release-branch>")
bash ~/.claude/skills/gitf/gitf-state.sh put "<release-branch>" \
  '{"flow":"B","step":"awaiting_merge_to_main","pr_number":<n>,"release_branch":"<release-branch>","target_branch":"main","version":<...>,"version_mode":<...>,"main_pr_merged":false,"pause_sha":"'"$pause_sha"'"}'
```

- [ ] **Step 4: Verify**

Run: `grep -rn 'gitf-state.sh put\|pause_sha' gitf/flows/`
Expected: every pause point in flow-a/b/c and code-review-gate writes via `put` and includes `pause_sha`.

- [ ] **Step 5: Commit**

```bash
git add gitf/flows/flow-a.md gitf/flows/flow-b.md gitf/flows/flow-c.md gitf/flows/code-review-gate.md
git commit -m "feat(gitf): pauses write branch-keyed entry with pause_sha

問題：我要支援多分支（每個分支各存一個 entry）

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 6: Idempotent probes on cache miss

**Files:**
- Modify: `gitf/providers/github.md`, `gitf/providers/local.md`

- [ ] **Step 1: Add PR-existence probe to github LAND**

In `gitf/providers/github.md`, before the `gh pr create` step in `LAND`, add:

```markdown
**Idempotency probe (cache-miss runs only).** Before creating a PR, check for an
existing one:

```bash
gh pr list --head <head> --base <base> --state all \
  --json number,state,mergeStateStatus
```

- an `OPEN` PR exists → skip `gh pr create`; use that PR number and check its
  `mergeStateStatus` (same as resume).
- a `MERGED` PR exists → this land already happened; skip to the next flow step.
- none → create the PR normally.

On a **cache hit** this probe is skipped — the entry already names the PR.
```

- [ ] **Step 2: Add tag + version probes note**

In `gitf/providers/github.md` `TAG`, add: "Idempotency: skip if `git tag -l v<version>` is non-empty." (local provider TAG too, Step 3.)

- [ ] **Step 3: Add already-merged probe to local LAND**

In `gitf/providers/local.md`, before the merge in `LAND`, add:

```markdown
**Idempotency probe (cache-miss runs only).** If `git log <base>..<head>` is
empty, `<head>` is already merged into `<base>` — skip the merge and proceed to
the next flow step. Also skip `TAG` when `git tag -l v<version>` is non-empty.
```

- [ ] **Step 4: Verify**

Run: `grep -rn 'Idempotency probe\|pr list --head\|tag -l' gitf/providers/`
Expected: github LAND has the PR probe, both providers have the tag probe, local has the merged probe.

- [ ] **Step 5: Commit**

```bash
git add gitf/providers/github.md gitf/providers/local.md
git commit -m "feat(gitf): idempotent LAND/TAG probes for cache-miss rebuild

問題：我要支援多分支（state 遺失時從 git/gh 現況安全重建）

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 7: Version-bump probe + orphan-branch halt in flows

**Files:**
- Modify: `gitf/flows/flow-b.md`, `gitf/flows/flow-c.md`

- [ ] **Step 1: Add version-bump probe to B-3**

In `gitf/flows/flow-b.md` B-3, prepend: "Idempotency (cache-miss): if the version file already equals `<new-version>` or a `chore: bump version` commit already exists on this branch, skip B-3."

- [ ] **Step 2: Add orphan-branch halt to flow-b.md**

Add to `gitf/flows/flow-b.md`, before B-1:

```markdown
### B-0: Orphan-branch guard (cache-miss, when triggered from develop)

Before creating a release branch, probe for an existing unmerged release branch:

```bash
git branch --list 'release/*' | while read -r b; do
  [ -n "$(git log main.."$b" --oneline)" ] && echo "ORPHAN:$b"
done
```

If any `ORPHAN:` printed → **halt**: tell the user an unfinished release branch
exists and to merge or delete it before running `/gitf` again. Do not create a
new release branch and do not append `-2`.
```

- [ ] **Step 3: Add orphan-branch halt to flow-c.md**

Add the equivalent guard to `gitf/flows/flow-c.md` before C-1, probing `hotfix/*` against `main`.

- [ ] **Step 4: Verify**

Run: `grep -n 'Orphan\|ORPHAN\|Idempotency' gitf/flows/flow-b.md gitf/flows/flow-c.md`
Expected: B-0 + B-3 probe in flow-b, orphan guard in flow-c.

- [ ] **Step 5: Commit**

```bash
git add gitf/flows/flow-b.md gitf/flows/flow-c.md
git commit -m "feat(gitf): version-bump probe + orphan-branch halt

問題：我要支援多分支（孤兒分支一律中斷不臆測）

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 8: GC entry on CLEANUP (hygiene)

**Files:**
- Modify: `gitf/providers/github.md`, `gitf/providers/local.md`

- [ ] **Step 1: Append entry-delete to CLEANUP**

In both `gitf/providers/github.md` and `gitf/providers/local.md`, at the end of the `CLEANUP branch` verb, add:

```bash
# Hygiene: drop this branch's state entry so a future same-named branch
# can never get a false cache hit.
bash ~/.claude/skills/gitf/gitf-state.sh del "<branch>"
```

- [ ] **Step 2: Verify**

Run: `grep -rn 'gitf-state.sh del' gitf/providers/ gitf/flows/`
Expected: CLEANUP in both providers and the completion points in resume.md call `del`.

- [ ] **Step 3: Commit**

```bash
git add gitf/providers/github.md gitf/providers/local.md
git commit -m "feat(gitf): GC state entry on branch cleanup

問題：我要支援多分支（gitf 自清 entry，避免僵屍）

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 9: Docs + spec sync

**Files:**
- Modify: `gitf/providers/README.md`, `spec/flows.md`, `spec/decision-tree.md`, `docs/usage.md`

- [ ] **Step 1: Update providers/README.md**

In the "State and resume" section, state that `.gitf/state.json` is a v2 branch-keyed map accessed via `gitf-state.sh`, that resume is by current branch with `pause_sha` validation, and that cache-miss rebuilds idempotently.

- [ ] **Step 2: Update spec/decision-tree.md**

Replace the platform-detection state paragraph: state is a branch-keyed map; Step 0.5 is a cache lookup (hit = entry + `pause_sha` ancestor → resume; miss → decision tree in idempotent mode). Add the halt-on-ambiguity rule under "Ambiguity resolution".

- [ ] **Step 3: Update spec/flows.md**

Update the "State file check" precondition and "State file lifecycle" to the v2 map model: entries created on pause (keyed by branch, with `pause_sha`), deleted on CLEANUP and flow completion, rebuilt idempotently when absent.

- [ ] **Step 4: Update docs/usage.md**

Add a short "Multiple branches in flight" note: each branch keeps its own paused state; `/gitf` acts on whichever branch you're on; abandoned branches are cleaned up automatically by gitf or ignored safely on the next run.

- [ ] **Step 5: Verify**

Run: `grep -rn 'branch-keyed\|gitf-state.sh\|pause_sha' spec/ docs/ gitf/providers/README.md`
Expected: each file references the new model; no doc still claims a single global state object.

- [ ] **Step 6: Commit**

```bash
git add gitf/providers/README.md spec/flows.md spec/decision-tree.md docs/usage.md
git commit -m "docs(gitf): document branch-keyed state, cache semantics, halt rule

問題：我要支援多分支

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 10: Full verification

**Files:** none (verification only)

- [ ] **Step 1: Run both test suites**

Run: `bash gitf/tests/test-detect.sh && bash gitf/tests/test-state.sh`
Expected: both print `FAIL=0` and exit 0.

- [ ] **Step 2: Grep for leftover single-state assumptions**

Run: `grep -rn 'never writes state\|single' gitf/ spec/ | grep -iv 'single-line\|single file holds'`
Expected: no remaining claim that state is a single global object or that local never writes state (local writes for `awaiting_code_review`).

- [ ] **Step 3: Confirm `gitf-state.sh` is executable and shipped**

Run: `test -x gitf/gitf-state.sh && echo OK`
Expected: `OK`.

- [ ] **Step 4: Bump skill `.version`** (so installs pick up the new file set)

Edit `gitf/.version` to the next patch/minor per the release convention; commit:

```bash
git add gitf/.version
git commit -m "chore(gitf): bump skill version for multi-branch state

問題：我要支援多分支

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Notes for the implementer

- `gitf-state.sh` is the ONLY way flows touch state — no flow hand-edits `.gitf/state.json`.
- `pause_sha` is captured at every pause and validated on every resume; this plus GC-on-cleanup are the two layers against same-name reuse.
- Cache hit = trust + resume (no extra git/gh derivation). Cache miss = decision tree + idempotent probes.
- Tasks 1–2 are real TDD (red→green). Tasks 3–9 edit instruction markdown; their "tests" are the grep consistency checks plus `evals/evals.json` (extend evals if behavior changes warrant it).
- This branch (`feature/multibranch-state`) is off develop, which already contains the code-review gate + `.gitf/` work.
```
