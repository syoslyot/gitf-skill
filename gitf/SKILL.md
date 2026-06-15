---
name: gitf
description: Personal Git Flow automation — invoke with /gitf to automatically handle the entire Git Flow lifecycle. Use this skill whenever the user types /gitf, wants to push a feature or fix branch to develop, wants to release to main, or needs help completing a Git Flow step. Detects current branch state and executes the appropriate flow end-to-end: feature/fix PR to develop, or full release to main with version bump and tagging. Fully automatic — creates PRs, merges them, pulls, tags, cleans up, all without waiting for confirmation. If branch protection blocks auto-merge, saves state and resumes on next /gitf call.
---

# /gitf — Personal Git Flow Automation

Fully automatic Git Flow execution. Detect state → decide path → execute end-to-end without pausing.

---

## Step -1: Auto-update check (ALWAYS run this first, before everything else)

Run the update script silently in the background. It checks GitHub once per hour at most — if checked recently, it exits immediately with no network call:

```bash
bash ~/.claude/skills/gitf/gitf-update.sh
```

If the script prints a line starting with `gitf updated:` (e.g. `gitf updated: 0.1.0 → 0.2.0`), tell the user in one line: "gitf skill updated to v0.2.0 — using new version." Then continue normally with the rest of the flow using the instructions currently loaded in context (the update takes effect next session).

If the script prints nothing or fails: continue silently. Never block the flow for this.

---

## Step 0: Check for saved state (ALWAYS run this first)

Before anything else:

```bash
cat .git/gitf-state.json 2>/dev/null
```

If the file exists → go to **FLOW RESUME** immediately. Skip all other detection.

If the file does not exist → proceed to **Step 1**.

---

## State file format

Saved at `.git/gitf-state.json` whenever a PR cannot be auto-merged. Deleted when the full flow completes.

```json
{
  "flow": "A",
  "step": "awaiting_merge",
  "pr_number": 3,
  "source_branch": "feature/auth-jwt",
  "target_branch": "develop",
  "version": null,
  "release_branch": null,
  "main_pr_merged": false,
  "develop_pr_number": null
}
```

| Field | Description |
|-------|-------------|
| `flow` | A / B / C |
| `step` | `awaiting_merge` / `awaiting_merge_to_main` / `awaiting_merge_to_develop` |
| `pr_number` | The PR currently waiting |
| `source_branch` | Branch that was PR'd |
| `target_branch` | Base branch of the waiting PR |
| `version` | (Flow B/C only) version being released |
| `release_branch` | (Flow B/C only) e.g. `release/v1.2.0` |
| `main_pr_merged` | (Flow B only) whether release→main is done |
| `develop_pr_number` | (Flow B only) PR number for back-merge, once created |

---

## FLOW RESUME

Read `.git/gitf-state.json`, then check the waiting PR:

```bash
gh pr view <pr_number> --json state,mergeStateStatus,statusCheckRollup
```

Evaluate the result:

| `state` | `mergeStateStatus` | Action |
|---------|-------------------|--------|
| `MERGED` | — | PR is done → proceed to next step (see below) |
| `OPEN` | `BLOCKED` | Tell user: "PR #N is still waiting for review. Merge it on GitHub, then run /gitf again." |
| `OPEN` | `UNSTABLE` | Tell user: "CI failed on PR #N. Fix the failing checks, then run /gitf again." |
| `OPEN` | `UNKNOWN` or checks pending | Tell user: "CI is still running on PR #N. Wait for it to finish, then run /gitf again." |
| `CLOSED` (not merged) | — | Tell user: "PR #N was closed without merging. Run /gitf again to start fresh." → delete state file |

### What "next step" means per flow and step:

**Flow A — `awaiting_merge`** (feature/fix → develop):
- PR merged → `git checkout develop && git pull origin develop`
- Delete `.git/gitf-state.json`
- Report: done

**Flow B — `awaiting_merge_to_main`** (release → main):
- PR merged → tag main:
  ```bash
  git checkout main && git pull origin main
  git tag -a v<version> -m "v<version>"
  git push origin v<version>
  ```
- Create back-merge PR (release → develop), attempt auto-merge
- If auto-merge succeeds → cleanup, delete state
- If blocked → update state: `step=awaiting_merge_to_develop`, save `develop_pr_number`

**Flow B — `awaiting_merge_to_develop`** (back-merge → develop):
- PR merged → cleanup:
  ```bash
  git checkout develop && git pull origin develop
  git branch -d <release_branch> 2>/dev/null || true
  ```
- Delete `.git/gitf-state.json`
- Report: full release summary

**Flow C — `awaiting_merge`** (hotfix → main or → develop):
- Same pattern as Flow B, using `target_branch` from state to know which step

---

## Step 1: Detect current state

Run in parallel:

```bash
git branch --show-current
git status --short
git log develop..HEAD --oneline
git log main..develop --oneline
git remote -v
```

---

## Decision Tree

```
/gitf triggered
│
├── .git/gitf-state.json exists? → FLOW RESUME (above)
│
├── On feature/* or fix/*
│   └── → FLOW A
│
├── On hotfix/*
│   └── → FLOW C
│
├── On release/*
│   └── → FLOW B (resume in-progress release without state file)
│
├── On develop
│   ├── uncommitted changes → FLOW D, Case 1
│   ├── commits ahead of origin/develop → FLOW D, Case 2
│   ├── develop ahead of main → FLOW B
│   └── develop == main → "develop and main are in sync, nothing to release"
│
└── On main → warn: "You're on main — should not be working here directly"
```

---

## FLOW A: Feature/Fix → Develop

```bash
# 1. Push
git push -u origin <current-branch>

# 2. Create PR
gh pr create --base develop \
  --title "<conventional commits title from branch/commits>" \
  --body "<summarize commits>"

# 3. Attempt auto-merge
gh pr view <number> --json mergeStateStatus,state
```

If `mergeStateStatus == CLEAN` → merge immediately:
```bash
gh pr merge <number> --merge --delete-branch
git checkout develop && git pull origin develop
```

If blocked (BLOCKED / UNSTABLE / checks pending) → save state:
```bash
# Write .git/gitf-state.json
{
  "flow": "A",
  "step": "awaiting_merge",
  "pr_number": <number>,
  "source_branch": "<current-branch>",
  "target_branch": "develop",
  "version": null,
  "release_branch": null,
  "main_pr_merged": false,
  "develop_pr_number": null
}
```
Tell user what's blocking and to run `/gitf` after it's resolved.

**PR title convention**: derive from branch name and commits.
- `feature/auth-jwt` → `feat(auth): implement JWT authentication`
- `fix/map-markers` → `fix(map): correct marker positioning`

---

## FLOW B: Full Release to Main

### B-1: Detect version file

Check in order:
1. `package.json` — if `.ts/.js/.tsx/.jsx` files exist
2. `pyproject.toml` — if `.py` is the main language
3. `Cargo.toml` — if `.rs` is the main language
4. `VERSION` — fallback; create with `0.1.0` if none found

Determine bump from `git log main..develop --oneline`:
- Only `fix:` commits → patch
- Any `feat:` commit → minor
- `BREAKING CHANGE` in any commit body → major (ask user to confirm before proceeding)

### B-2: Create release branch and bump version

```bash
git checkout develop && git pull origin develop
git checkout -b release/v<new-version>
# Edit version file (only the version field)
git add <version-file>
git commit -m "chore: bump version to v<new-version>"
git push -u origin release/v<new-version>
```

### B-3: PR release → main

```bash
gh pr create --base main \
  --title "release: v<new-version>" \
  --body "Release v<new-version>

Changes since last release:
$(git log main..HEAD --oneline --no-merges)"

gh pr view <number> --json mergeStateStatus,state
```

If `CLEAN` → merge, then tag:
```bash
gh pr merge <number> --merge
git checkout main && git pull origin main
git tag -a v<new-version> -m "v<new-version>"
git push origin v<new-version>
```
Then proceed to B-4.

If blocked → save state:
```json
{
  "flow": "B",
  "step": "awaiting_merge_to_main",
  "pr_number": <number>,
  "source_branch": "release/v<new-version>",
  "target_branch": "main",
  "version": "<new-version>",
  "release_branch": "release/v<new-version>",
  "main_pr_merged": false,
  "develop_pr_number": null
}
```

### B-4: PR release → develop (back-merge)

After tagging, the current branch is `main`. Must explicitly specify `--head` so GitHub uses the release branch, not main:

```bash
gh pr create --base develop \
  --head release/v<new-version> \
  --title "chore: back-merge release v<new-version> into develop" \
  --body "Brings version bump commit from release/v<new-version> back to develop"

gh pr view <number> --json mergeStateStatus,state
```

If `CLEAN` → merge and clean up:
```bash
gh pr merge <number> --merge
git push origin --delete release/v<new-version>
git checkout develop && git pull origin develop
git branch -d release/v<new-version> 2>/dev/null || true
```
Delete `.git/gitf-state.json`. Report full release summary.

If blocked → update state:
```json
{
  "flow": "B",
  "step": "awaiting_merge_to_develop",
  "pr_number": <develop-pr-number>,
  "source_branch": "release/v<new-version>",
  "target_branch": "develop",
  "version": "<new-version>",
  "release_branch": "release/v<new-version>",
  "main_pr_merged": true,
  "develop_pr_number": <number>
}
```

### B-5: Final confirmation (after cleanup)

```
✓ Released v<new-version>
  • release/v<new-version> merged to main
  • Tagged v<new-version> on main
  • Version bump back-merged to develop
  • Release branch deleted (local + remote)
  • develop and main are now in sync
```

---

## FLOW C: Hotfix

```bash
git push -u origin <hotfix-branch>

# PR to main
gh pr create --base main --title "hotfix: <description>" --body "..."
# Check mergeStateStatus, save state if blocked (same pattern as Flow A)
gh pr merge <number> --merge

# Tag
git checkout main && git pull origin main
git tag -a v<bumped-patch> -m "v<bumped-patch>"
git push origin v<bumped-patch>

# PR to develop
gh pr create --base develop --title "hotfix: back-merge <description> to develop" --body "..."
# Check mergeStateStatus, save state if blocked
gh pr merge <number> --merge --delete-branch

git checkout develop && git pull origin develop
git branch -d <hotfix-branch>
```

---

## FLOW D: Rescue — AI Forgot to Branch

**Case 1 — uncommitted changes on develop:**
```bash
git checkout -b <inferred-branch>
# Changes carry over automatically
```
Then FLOW A.

**Case 2 — rogue commits on develop:**
```bash
git checkout -b <inferred-branch>   # at current HEAD
git checkout develop
git reset --hard origin/develop
git checkout <inferred-branch>
```
Then FLOW A.

**Branch naming**: infer from commit messages and changed files. Format: `feature/<scope>-<kebab-desc>` or `fix/<scope>-<kebab-desc>`. Tell the user the chosen name and why.

---

## Rules

- Never commit directly to `develop` or `main`
- `feature/*` and `fix/*` always branch from develop, never from main
- Merge type is always merge commit (`--merge`)
- Tag immediately after merge to main, before back-merge to develop
- Delete release/feature/fix branches after flow completes (local and remote)
- Check `mergeStateStatus` before attempting `gh pr merge` — never blindly call merge and hope it works
- Delete `.git/gitf-state.json` only when the entire flow is fully complete
- If `gh` is not authenticated or a PR creation fails, stop and report the error clearly
