---
name: gitf
description: Personal Git Flow automation — invoke with /gitf to automatically handle the entire Git Flow lifecycle. Use this skill whenever the user types /gitf, wants to push a feature or fix branch to develop, wants to release to main, or needs help completing a Git Flow step. Detects current branch state and executes the appropriate flow end-to-end: feature/fix PR to develop, or full release to main with version bump and tagging. Fully automatic — creates PRs, merges them, pulls, tags, cleans up, all without waiting for confirmation.
---

# /gitf — Personal Git Flow Automation

Fully automatic Git Flow execution. Detect state → decide path → execute end-to-end without pausing.

## Step 0: Detect State

Run these in parallel to understand the current situation:

```bash
git branch --show-current          # current branch name
git status --short                  # uncommitted changes
git log develop..HEAD --oneline    # commits on current branch not yet in develop
git log main..develop --oneline    # commits in develop not yet in main
```

Also check which remote tracking exists:
```bash
git remote -v
```

---

## Decision Tree

```
/gitf triggered
│
├── On feature/* or fix/*
│   └── → FLOW A: Merge to Develop
│
├── On hotfix/*
│   └── → FLOW C: Hotfix
│
├── On release/*
│   └── → FLOW B (continue): Complete in-progress release
│
├── On develop
│   ├── Has uncommitted changes OR has commits not in develop (AI forgot to branch)
│   │   └── → FLOW D: Rescue — create branch, move commits, then FLOW A
│   ├── develop is ahead of main (git log main..develop shows commits)
│   │   └── → FLOW B: Full Release to Main
│   └── develop == main (nothing to release)
│       └── → Tell user: "develop and main are in sync, nothing to release"
│
└── On main
    └── → Warn: "You're on main — should not be working here directly"
```

---

## FLOW A: Feature/Fix → Develop

Goal: push current branch, open PR to develop, merge, pull develop.

```bash
# 1. Push branch
git push -u origin <current-branch>

# 2. Create PR targeting develop
gh pr create --base develop --title "<derive from branch name>" --body "<summarize commits>"

# 3. Merge PR immediately (merge commit)
gh pr merge <PR-number> --merge --delete-branch

# 4. Sync local develop
git checkout develop
git pull origin develop
```

**PR title convention**: derive from branch name and commits. Examples:
- `feature/auth-jwt` → `feat(auth): implement JWT authentication`
- `fix/map-markers` → `fix(map): correct marker positioning`

**After merge**: confirm to user with one line — which branch was merged and that develop is now up to date.

---

## FLOW B: Full Release to Main

Goal: branch release, bump version, PR to main, tag, PR to develop, clean up.

### B-1: Detect version and determine next version

First, find the version file by checking in order:
1. `package.json` (if `.ts`, `.js`, `.tsx`, `.jsx` files exist in project root or `src/`)
2. `pyproject.toml` (if `.py` files are the main language)
3. `Cargo.toml` (if `.rs` files are the main language)
4. `VERSION` (fallback, create if none of the above exist)

Read current version, then determine bump type:
- **patch** (x.y.**Z**): bug fixes only since last release
- **minor** (x.**Y**.0): new features added since last release
- **major** (**X**.0.0): breaking changes (rare, ask user to confirm)

Look at `git log main..develop --oneline` to decide. If unsure between patch and minor, lean toward minor.

### B-2: Create release branch and bump version

```bash
git checkout develop
git pull origin develop
git checkout -b release/v<new-version>
```

Update the version file (only the version field, nothing else):
- `package.json`: change `"version": "..."` field
- `pyproject.toml`: change `version = "..."` field  
- `Cargo.toml`: change `version = "..."` field
- `VERSION`: overwrite file content with new version

```bash
git add <version-file>
git commit -m "chore: bump version to v<new-version>"
git push -u origin release/v<new-version>
```

### B-3: PR release → main, merge, tag

```bash
# Create PR to main
gh pr create --base main \
  --title "release: v<new-version>" \
  --body "Release v<new-version>

Changes since last release:
$(git log main..HEAD --oneline --no-merges)"

# Merge immediately (merge commit)
gh pr merge <PR-number> --merge

# Switch to main, pull, tag
git checkout main
git pull origin main
git tag -a v<new-version> -m "v<new-version>"
git push origin v<new-version>
```

### B-4: PR release → develop (back-merge), merge, clean up

```bash
# Create back-merge PR
gh pr create --base develop \
  --title "chore: back-merge release v<new-version> into develop" \
  --body "Brings version bump commit from release/v<new-version> back to develop"

# Merge immediately
gh pr merge <PR-number> --merge --delete-branch

# Sync local develop, clean up local release branch
git checkout develop
git pull origin develop
git branch -d release/v<new-version>
```

### B-5: Final confirmation

Report to user:
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

Goal: critical production fix from main, merge to both main and develop.

```bash
# Assumes user is already on hotfix/* branch with commits
git push -u origin <hotfix-branch>

# PR to main
gh pr create --base main --title "hotfix: <description>" --body "..."
gh pr merge <PR-number> --merge

# Tag on main
git checkout main && git pull origin main
git tag -a v<bumped-patch> -m "v<bumped-patch>"
git push origin v<bumped-patch>

# PR to develop
gh pr create --base develop --title "hotfix: back-merge <description> to develop" --body "..."
gh pr merge <PR-number> --merge --delete-branch

git checkout develop && git pull origin develop
git branch -d <hotfix-branch>
```

---

## FLOW D: Rescue — AI Forgot to Branch

Triggered when: on `develop` and there are commits that don't belong there, OR there are uncommitted changes.

### Case 1: Uncommitted changes on develop

```bash
# Determine branch name from context (file names, nature of changes)
# Name format: feature/<scope>-<desc> or fix/<scope>-<desc>
git checkout -b <new-branch>
# All uncommitted changes are now on the new branch
```
Then execute **FLOW A**.

### Case 2: Commits already on develop that shouldn't be there

```bash
# Find where develop diverged from origin/develop
git log origin/develop..develop --oneline  # shows the rogue commits

# Create new branch at current HEAD
git checkout -b <new-branch>

# Reset develop back to origin/develop
git checkout develop
git reset --hard origin/develop

# Switch back to new branch (commits are preserved there)
git checkout <new-branch>
```
Then execute **FLOW A**.

**Branch naming**: analyze the commit messages and changed files to infer a meaningful name. Format: `feature/<scope>-<kebab-desc>` or `fix/<scope>-<kebab-desc>`. Tell the user what branch was created and why that name was chosen.

---

## Rules

- **Never commit directly to `develop` or `main`** — all changes go through branches and PRs
- **feature/* and fix/* always branch from develop**, never from main
- **Merge type is always merge commit** (`--merge` flag, not `--squash` or `--rebase`)
- **Tag immediately after merge to main**, before the back-merge to develop
- **Delete release/feature/fix branches** after both PRs merge (local and remote)
- **All operations are automatic** — do not pause to ask for confirmation mid-flow
- If `gh` is not authenticated or a PR creation fails, stop and report the error clearly
