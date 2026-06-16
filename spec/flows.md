# Flow Specifications

Formal specification for each flow in `/gitf`. These define expected behavior for evals and contributors.

> **Platform note.** The GitHub commands below describe the `github` provider.
> Flows themselves are written against platform-agnostic coarse verbs
> (`LAND`/`PUBLISH`/`SYNC`/`TAG`/`CLEANUP`) — see `gitf/flows/` and
> `gitf/providers/`. The `local` provider replaces each `gh` PR cycle with a
> synchronous `git merge --no-ff` and never blocks on a PR. The spec below is the
> GitHub-provider reference; for the verb contract see
> `gitf/providers/README.md`.

---

## Precondition: State lookup (cache hit / miss)

Before every flow, look up the **current branch's** entry in the v2 branch-keyed
map `.gitf/state.json` via `gitf-state.sh get <branch>`. If an entry exists and
its `pause_sha` is still an ancestor of the current tip (`gitf-state.sh valid`),
that is a **cache hit** → go to **FLOW RESUME**. Otherwise (no entry, or a reused
branch name whose `pause_sha` no longer applies) it is a **cache miss** → run
normal detection; the chosen flow runs idempotently and halts on ambiguity.

Entries are written when a flow pauses — by the `github` provider's caller for
PR-merge pauses, and by the code-review gate for the code-review pause
(`step=awaiting_code_review`, **either** provider, since the review runs on the
local branch before landing on `main`). A v1 (non-`flows`) file is treated as
empty, so it is always a cache miss — that is the migration path.

---

## FLOW RESUME

Read the current branch's entry (`gitf-state.sh get <branch>`). For a code-review
pause (`step=awaiting_code_review`) there is no PR — re-run the gate (see below).
Otherwise check the waiting PR:

```bash
gh pr view <pr_number> --json state,mergeStateStatus,statusCheckRollup
```

| `state` | `mergeStateStatus` | Action |
|---------|-------------------|--------|
| `MERGED` | — | Continue to next step for this flow+step |
| `OPEN` | `BLOCKED` | Report: waiting for review |
| `OPEN` | `UNSTABLE` | Report: CI failed |
| `OPEN` | `UNKNOWN` / pending | Report: CI still running |
| `CLOSED` (not merged) | — | Report: PR closed without merge → drop the branch's entry |

### Next steps by flow and step

| Flow | Step | Next action after PR merged |
|------|------|-----------------------------|
| A | `awaiting_merge` | pull develop → drop entry |
| B | `awaiting_merge_to_main` | tag main → create back-merge PR → attempt merge or update entry |
| B | `awaiting_merge_to_develop` | pull develop → cleanup release branch → drop entry → report |
| C | `awaiting_merge` (to main) | tag main → create back-merge PR → attempt merge or update entry |
| C | `awaiting_merge` (to develop) | pull develop → cleanup → drop entry |

For `step=awaiting_code_review` there is no PR. Re-run the code-review gate on
the release/hotfix branch; if it passes, resume the flow at the land-to-main
step; if it stops again, leave state in place and halt.

---

## Flow A — Feature/Fix → Develop

**Trigger**: on `feature/*` or `fix/*`

**Steps**:
1. `git push -u origin <branch>`
2. `gh pr create --base develop` — title from branch/commits (Conventional Commits format)
3. Check `mergeStateStatus` before attempting merge:
   - `CLEAN` → `gh pr merge <number> --merge --delete-branch` → pull develop
   - Otherwise → save state, report blocking reason

**Postconditions (success)**:
- Feature/fix branch deleted on remote
- Local develop in sync with origin/develop
- `.gitf/state.json` does not exist

**Postconditions (blocked)**:
- PR exists on GitHub
- `.gitf/state.json` saved with `step: "awaiting_merge"`
- User told what's blocking and what to do

---

## Flow B — Full Release to Main

**Trigger**: on `develop` with commits ahead of `main`, or on existing `release/*` branch

### B-1: Version detection

Priority order:
1. `package.json` — if `.ts/.js/.tsx/.jsx` files exist
2. `pyproject.toml` — if `.py` is primary language
3. `Cargo.toml` — if `.rs` is primary language
4. `VERSION` — fallback; create with `0.1.0` if missing

Bump type from `git log main..develop --oneline`:
- Only `fix:` commits → patch
- Any `feat:` → minor
- `BREAKING CHANGE` in body → major (confirm with user)

### B-2: Release branch

```
git checkout develop && git pull
git checkout -b release/v<version>
<edit version field only in version file>
git add <file> && git commit -m "chore: bump version to v<version>"
git push -u origin release/v<version>
```

### B-2.5: Code-review gate

Run the configured reviewers (`.gitf/config` → `reviewers`) on
`main..release/v<version>`. The AI judges each tool's output:
- no blocking findings → proceed to B-3
- findings it can fix → fix, commit to the release branch, re-run that reviewer
- findings needing the user → save state (`step: awaiting_code_review`) and stop

Skipped when `reviewers` is empty or `--skip-review` was passed.

### B-3: PR release → main

Check `mergeStateStatus`:
- `CLEAN` → merge → pull main → tag `v<version>` → push tag → proceed to B-4
- Blocked → save state (`step: awaiting_merge_to_main`, `main_pr_merged: false`)

### B-4: PR release → develop

Check `mergeStateStatus`:
- `CLEAN` → merge → pull develop → delete release branch (local + remote) → delete state → report
- Blocked → update state (`step: awaiting_merge_to_develop`, `develop_pr_number: <n>`, `main_pr_merged: true`)

**Note**: tag is always created between B-3 and B-4. Never before B-3 merges, never after B-4.

**Postconditions (success)**:
- `main` contains release commit + version bump, tagged `v<version>`
- `develop` contains version bump via back-merge
- Release branch deleted local and remote
- `.gitf/state.json` does not exist

---

## Flow C — Hotfix

**Trigger**: on `hotfix/*`

Same two-PR pattern as Flow B, but:
- Code-review gate runs on `main..hotfix/*` before the PR to `main` (same logic
  as B-2.5; can pause with `step: awaiting_code_review`)
- First PR targets `main`
- Version is always patch bump
- Tag after PR to main merges
- Second PR targets `develop`
- State file uses same fields, `target_branch` distinguishes the two steps

---

## Flow D — Rescue

**Trigger**: on `develop` with uncommitted changes (Case 1) or rogue commits (Case 2)

### Case 1 — Uncommitted changes

```bash
git checkout -b <inferred-name>
# Uncommitted changes follow automatically
```

Then Flow A.

### Case 2 — Rogue commits

```bash
git checkout -b <inferred-name>
git checkout develop
git reset --hard origin/develop
git checkout <inferred-name>
```

Then Flow A.

**Branch naming**: infer from commit messages + changed file paths. Format: `feature/<scope>-<desc>` or `fix/<scope>-<desc>`. Always report chosen name and reasoning to user.

**Postcondition**: `develop` is back in sync with `origin/develop`.

---

## State entry lifecycle

Each entry is keyed by its owning branch and carries `pause_sha` (the branch tip
at pause time). All access is via `gitf-state.sh`.

```
Created → when a PR is created but mergeStateStatus != CLEAN
        → when the code-review gate stops with unresolved findings (awaiting_code_review)
Updated → when moving between steps within Flow B (main_pr_merged, develop_pr_number)
Deleted → when the entry's flow completes successfully
         → when its branch is cleaned up (CLEANUP drops the entry)
         → when its PR is found CLOSED without merge (reset for fresh start)
```

An entry is never deleted mid-flow unless its PR was abandoned. On cache miss the
flow rebuilds progress idempotently rather than relying on a stored entry.
