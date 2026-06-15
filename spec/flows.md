# Flow Specifications

Formal specification for each flow in `/gitf`. These define expected behavior for evals and contributors.

---

## Precondition: State file check

Before every flow, check `.git/gitf-state.json`. If it exists, go to **FLOW RESUME** instead of running normal detection.

---

## FLOW RESUME

Read state file. Check waiting PR:

```bash
gh pr view <pr_number> --json state,mergeStateStatus,statusCheckRollup
```

| `state` | `mergeStateStatus` | Action |
|---------|-------------------|--------|
| `MERGED` | — | Continue to next step for this flow+step |
| `OPEN` | `BLOCKED` | Report: waiting for review |
| `OPEN` | `UNSTABLE` | Report: CI failed |
| `OPEN` | `UNKNOWN` / pending | Report: CI still running |
| `CLOSED` (not merged) | — | Report: PR closed without merge → delete state file |

### Next steps by flow and step

| Flow | Step | Next action after PR merged |
|------|------|-----------------------------|
| A | `awaiting_merge` | pull develop → delete state |
| B | `awaiting_merge_to_main` | tag main → create back-merge PR → attempt merge or save state |
| B | `awaiting_merge_to_develop` | pull develop → cleanup release branch → delete state → report |
| C | `awaiting_merge` (to main) | tag main → create back-merge PR → attempt merge or save state |
| C | `awaiting_merge` (to develop) | pull develop → cleanup → delete state |

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
- `.git/gitf-state.json` does not exist

**Postconditions (blocked)**:
- PR exists on GitHub
- `.git/gitf-state.json` saved with `step: "awaiting_merge"`
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
- `.git/gitf-state.json` does not exist

---

## Flow C — Hotfix

**Trigger**: on `hotfix/*`

Same two-PR pattern as Flow B, but:
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

## State file lifecycle

```
Created → when a PR is created but mergeStateStatus != CLEAN
Updated → when moving between steps within Flow B (main_pr_merged, develop_pr_number)
Deleted → when the entire flow completes successfully
         → when a PR is found CLOSED without merge (reset for fresh start)
```

State file is never deleted mid-flow unless the PR was abandoned.
