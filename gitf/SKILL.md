---
name: gitf
description: Personal Git Flow automation — invoke with /gitf to automatically handle the entire Git Flow lifecycle. Use this skill whenever the user types /gitf or /gitf -v. Detects current branch state and executes the appropriate flow end-to-end: feature/fix PR to develop, or full release to main. Default /gitf releases without version bump or tag; /gitf -v bumps version and creates a git tag. Fully automatic — creates PRs, merges them, pulls, tags, cleans up, without waiting for confirmation. If branch protection blocks auto-merge, saves state to .git/gitf-state.json and resumes on next /gitf call.
---

# /gitf — Personal Git Flow Automation

Fully automatic Git Flow. Detect state → decide path → execute end-to-end without pausing.

---

## Step -1: Auto-update check (ALWAYS run first)

```bash
bash ~/.claude/skills/gitf/gitf-update.sh
```

If output starts with `gitf updated:` → tell user in one line and continue. If nothing or fails → continue silently.

---

## Step 0: Check for saved state

```bash
cat .git/gitf-state.json 2>/dev/null
```

If file exists → go to **FLOW RESUME** immediately.
If not → proceed to **Step 0.5**.

---

## Step 0.5: Parse flags

Check whether the user's invocation was `/gitf -v` or just `/gitf`:

- `/gitf -v` → `VERSION_MODE=true`
- `/gitf` → `VERSION_MODE=false`

`-v` only affects the release flow (Flow B). All other flows ignore it silently.

---

## State file

Saved at `.git/gitf-state.json` when a PR cannot be auto-merged. Deleted when the full flow completes.

```json
{
  "flow": "A",
  "step": "awaiting_merge",
  "pr_number": 3,
  "source_branch": "feature/auth-jwt",
  "target_branch": "develop",
  "release_branch": null,
  "version": null,
  "version_mode": false,
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
| `release_branch` | (Flow B/C) e.g. `release/2026-06-15` or `release/v1.2.0` |
| `version` | (Flow B/C, version_mode only) version string e.g. `1.2.0` |
| `version_mode` | Whether `-v` was passed — determines tagging behavior on resume |
| `main_pr_merged` | (Flow B) whether release→main is done |
| `develop_pr_number` | (Flow B) PR number for back-merge, once created |

---

## FLOW RESUME

Read state file. Check waiting PR:

```bash
gh pr view <pr_number> --json state,mergeStateStatus,statusCheckRollup
```

| `state` | `mergeStateStatus` | Action |
|---------|-------------------|--------|
| `MERGED` | — | Continue to next step (see table below) |
| `OPEN` | `BLOCKED` | → see **Status Messages: blocked-review** |
| `OPEN` | `UNSTABLE` | → see **Status Messages: blocked-ci-failed** |
| `OPEN` | `UNKNOWN` / pending | → see **Status Messages: blocked-ci-running** |
| `CLOSED` (not merged) | — | → see **Status Messages: pr-closed** → delete state file |

### Resume actions by flow + step

| Flow | Step | Action after PR merged |
|------|------|------------------------|
| A | `awaiting_merge` | Pull develop → delete state → **Status: flow-a-done** |
| B | `awaiting_merge_to_main` | Tag if `version_mode=true` → open back-merge PR → merge or save state → **Status: flow-b-done** or save state |
| B | `awaiting_merge_to_develop` | Cleanup → delete state → **Status: flow-b-done** |
| C | `awaiting_merge` (to main) | Tag → open back-merge PR → merge or save state |
| C | `awaiting_merge` (to develop) | Cleanup → delete state → **Status: flow-c-done** |

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
├── .git/gitf-state.json exists? → FLOW RESUME
│
├── On feature/* or fix/*  → FLOW A
├── On hotfix/*            → FLOW C
├── On release/*           → FLOW B (B-4 onwards, release branch already exists)
│
├── On develop
│   ├── uncommitted changes              → FLOW D, Case 1
│   ├── commits ahead of origin/develop  → FLOW D, Case 2
│   ├── develop ahead of main            → FLOW B (full, from B-1)
│   └── develop == main                  → Status: nothing-to-do
│
└── On main → Status: warn-on-main
```

---

## FLOW A: Feature/Fix → Develop

```bash
# 1. Push
git push -u origin <current-branch>

# 2. Create PR
gh pr create --base develop \
  --title "<conventional commits title>" \
  --body "<summarize commits>"

# 3. Check before merging
gh pr view <number> --json mergeStateStatus,state
```

If `CLEAN` → merge:
```bash
gh pr merge <number> --merge --delete-branch
git checkout develop && git pull origin develop
```
→ **Status: flow-a-done**

If blocked → save state (`flow=A, step=awaiting_merge`) → **Status: blocked-\***

**PR title**: derive from branch name using Conventional Commits.
- `feature/auth-jwt` → `feat(auth): implement JWT authentication`
- `fix/map-markers` → `fix(map): correct marker positioning`

---

## FLOW B: Release

Flow B is split into shared steps (always run) and version-only steps (run only when `VERSION_MODE=true`). The steps marked **[version only]** are skipped when `-v` was not passed.

### B-1: Determine release name

**[version only]**: Read version file (see detection order below), determine bump from commit history, compute new version. Release branch = `release/v<new-version>`.

**[no version]**: Release branch = `release/<YYYY-MM-DD>`. If that branch name already exists on remote, append `-2`, `-3`, etc.

Version file detection order:
1. `package.json` (if `.ts/.js/.tsx/.jsx` files exist)
2. `pyproject.toml` (if `.py` is primary language)
3. `Cargo.toml` (if `.rs` is primary language)
4. `VERSION` (fallback — create with `0.1.0` if none found)

Bump type from `git log main..develop --oneline`:
- Only `fix:` commits → patch
- Any `feat:` → minor
- `BREAKING CHANGE` in body → major (confirm with user first)

### B-2: Create release branch

```bash
git checkout develop && git pull origin develop
git checkout -b <release-branch-name>
```

### B-3 [version only]: Bump version file

Edit only the version field in the detected file:
- `package.json` → `"version": "<new-version>"`
- `pyproject.toml` → `version = "<new-version>"`
- `Cargo.toml` → `version = "<new-version>"`
- `VERSION` → overwrite with `<new-version>`

```bash
git add <version-file>
git commit -m "chore: bump version to v<new-version>"
```

### B-4: Push release branch

```bash
git push -u origin <release-branch-name>
```

### B-5: PR release → main

```bash
gh pr create --base main \
  --title "<release: v<version> | merge: <release-branch-name>>" \
  --body "$(git log main..HEAD --oneline --no-merges)"

gh pr view <number> --json mergeStateStatus,state
```

If `CLEAN` → merge:
```bash
gh pr merge <number> --merge
git checkout main && git pull origin main
```
Then → B-6.

If blocked → save state:
```json
{
  "flow": "B", "step": "awaiting_merge_to_main",
  "pr_number": <n>, "source_branch": "<release-branch>",
  "target_branch": "main", "release_branch": "<release-branch>",
  "version": "<version-or-null>", "version_mode": <true|false>,
  "main_pr_merged": false, "develop_pr_number": null
}
```
→ **Status: blocked-\***

### B-6 [version only]: Tag main

```bash
git tag -a v<version> -m "v<version>"
git push origin v<version>
```

### B-7: PR release → develop (back-merge)

Must specify `--head` explicitly — current branch may be `main` at this point:

```bash
gh pr create --base develop \
  --head <release-branch-name> \
  --title "chore: back-merge <release-branch-name> into develop" \
  --body "Syncs release changes back to develop"

gh pr view <number> --json mergeStateStatus,state
```

If `CLEAN` → merge → B-8.

If blocked → update state:
```json
{
  "step": "awaiting_merge_to_develop",
  "pr_number": <n>, "main_pr_merged": true,
  "develop_pr_number": <n>
}
```
→ **Status: blocked-\***

### B-8: Cleanup

```bash
git push origin --delete <release-branch-name>
git checkout develop && git pull origin develop
git branch -d <release-branch-name> 2>/dev/null || true
```

Delete `.git/gitf-state.json` → **Status: flow-b-done**

---

## FLOW C: Hotfix

Hotfix always uses version mode (patching production always gets a tag):

```bash
git push -u origin <hotfix-branch>
```

Determine patch-bumped version (same detection as B-1, always patch bump).

```bash
# PR to main
gh pr create --base main --title "hotfix: <description>"
gh pr view <number> --json mergeStateStatus,state
# If CLEAN:
gh pr merge <number> --merge
git checkout main && git pull origin main
git tag -a v<patch-version> -m "v<patch-version>"
git push origin v<patch-version>

# PR to develop
gh pr create --base develop \
  --head <hotfix-branch> \
  --title "hotfix: back-merge <description> to develop"
gh pr view <number> --json mergeStateStatus,state
# If CLEAN:
gh pr merge <number> --merge
git checkout develop && git pull origin develop
git branch -d <hotfix-branch>
```

Save state on any blocked step (same pattern as Flow B).

→ **Status: flow-c-done**

---

## FLOW D: Rescue — AI Forgot to Branch

**Case 1 — uncommitted changes on develop:**
```bash
git checkout -b <inferred-name>
```
Infer branch name from staged/unstaged file content. Tell user the chosen name and why.
Then → FLOW A.

**Case 2 — rogue commits on develop:**
```bash
git checkout -b <inferred-name>
git checkout develop
git reset --hard origin/develop
git checkout <inferred-name>
```
Infer name from commit messages. Tell user what was moved.
Then → FLOW A.

Branch format: `feature/<scope>-<kebab-desc>` or `fix/<scope>-<kebab-desc>`.

---

## Status Messages

All post-flow messages go here. Each flow references these by name.

### flow-a-done
```
✓ <branch-name> merged to develop.
  develop is ahead of main — run /gitf to release, or /gitf -v to release with a version tag.
```

### flow-b-done (no version)
```
✓ <release-branch> merged to main and develop.
  main and develop are in sync.
```

### flow-b-done (version)
```
✓ Released v<version>
  main and develop are in sync.
```

### flow-c-done
```
✓ Hotfix v<version> applied to main and develop.
  main and develop are in sync.
```

### nothing-to-do
```
develop and main are already in sync — nothing to release.
```

### warn-on-main
```
⚠ You're on main — work should happen on feature/* or fix/* branches off develop.
```

### blocked-review
```
⏸ PR #<n> is waiting for review.
  Once it's approved and merged on GitHub, run /gitf to continue.
  Next: <what will happen — e.g. "develop will be synced" / "release will be tagged and back-merged to develop">
```

### blocked-ci-failed
```
⏸ PR #<n> — CI failed.
  Fix the failing checks, then run /gitf to continue.
```

### blocked-ci-running
```
⏸ PR #<n> — CI is still running.
  Once all checks pass, run /gitf to continue.
```

### pr-closed
```
PR #<n> was closed without merging. State cleared.
Run /gitf again to start fresh.
```

---

## Rules

- **This skill runs ONLY when the user explicitly types `/gitf` or `/gitf -v`.** Never invoke this flow automatically. Do not write instructions into any project's CLAUDE.md, AGENTS.md, or similar files that would cause an AI agent to trigger this skill without an explicit user command.
- Never commit directly to `develop` or `main`
- `feature/*` and `fix/*` always branch from develop, never from main
- Merge type is always merge commit (`--merge`)
- **[version only]** Tag immediately after merge to main, before back-merge to develop
- Always specify `--head <release-branch>` when creating the back-merge PR (current branch may be `main` at that point)
- Delete release/feature/fix branches after flow completes (local and remote)
- Check `mergeStateStatus` before calling `gh pr merge` — never attempt merge blindly
- Delete `.git/gitf-state.json` only when the entire flow is fully complete
- If `gh` is not authenticated or a PR creation fails, stop and report the error clearly
