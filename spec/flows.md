# Flow Specifications

Formal specification for each flow in `/gitf`. These define expected behavior for evals and contributors.

---

## Flow A — Feature/Fix → Develop

**Trigger**: on `feature/*` or `fix/*`

**Steps** (in order, no pausing):
1. `git push -u origin <branch>` — push current branch to remote
2. `gh pr create --base develop` — title derived from branch name using Conventional Commits format; body summarizes commits
3. `gh pr merge <number> --merge --delete-branch` — merge commit, delete remote branch
4. `git checkout develop && git pull origin develop` — sync local

**PR title derivation**:
- Strip prefix and slashes: `feature/auth-jwt` → scope=`auth`, description=`jwt`
- Apply conventional commits: `feat(auth): implement jwt` → capitalize properly
- If commits give more context, prefer commit summary over branch name

**Postconditions**:
- Feature/fix branch deleted on remote
- Local develop is up to date with origin/develop
- User sees one confirmation line

---

## Flow B — Full Release to Main

**Trigger**: on `develop`, `develop` ahead of `main`; OR resuming an existing `release/*` branch

**Steps**:

### B-1 Version detection
Check project root for version files in priority order:
1. `package.json` — present if `.ts/.js/.tsx/.jsx` files exist
2. `pyproject.toml` — present if `.py` files are primary language
3. `Cargo.toml` — present if `.rs` files are primary language
4. `VERSION` — fallback; create with `0.1.0` if no file found

Determine bump type from `git log main..develop --oneline`:
- Only `fix:` commits → patch
- Any `feat:` commit → minor
- Any `BREAKING CHANGE` in body → major (confirm with user before proceeding)

### B-2 Release branch
```
git checkout develop && git pull origin develop
git checkout -b release/v<new-version>
<edit version file — only the version field>
git add <version-file>
git commit -m "chore: bump version to v<new-version>"
git push -u origin release/v<new-version>
```

### B-3 Merge to main + tag
```
gh pr create --base main --title "release: v<new-version>"
gh pr merge <number> --merge
git checkout main && git pull origin main
git tag -a v<new-version> -m "v<new-version>"
git push origin v<new-version>
```

### B-4 Back-merge to develop + cleanup
```
gh pr create --base develop --title "chore: back-merge release v<new-version> into develop"
gh pr merge <number> --merge --delete-branch
git checkout develop && git pull origin develop
git branch -d release/v<new-version>
```

**Postconditions**:
- `main` contains the release commit + version bump
- `main` is tagged `v<new-version>`
- `develop` contains the version bump (via back-merge)
- `release/v<new-version>` deleted local and remote
- User sees full release summary

---

## Flow C — Hotfix

**Trigger**: on `hotfix/*`

**Steps**:
1. Push hotfix branch
2. PR to `main`, merge
3. Pull main, create patch-bumped tag, push tag
4. PR to `develop`, merge, delete branch
5. Pull develop, delete local hotfix branch

**Version**: always patch bump, read from same version file detection as Flow B.

---

## Flow D — Rescue

**Trigger**: on `develop` with uncommitted changes (Case 1) or rogue commits (Case 2)

### Case 1 — Uncommitted changes
```
git checkout -b <inferred-branch-name>
```
Branch name inferred from: staged/unstaged file paths and content. Format: `feature/<scope>-<kebab-desc>` or `fix/<scope>-<kebab-desc>`. Tell user the chosen name and reasoning.

Then execute **Flow A**.

### Case 2 — Rogue commits on develop
```
git checkout -b <inferred-branch-name>    # at current HEAD
git checkout develop
git reset --hard origin/develop            # restore develop to remote state
git checkout <new-branch>
```
Branch name inferred from commit messages. Tell user what was moved and why the name was chosen.

Then execute **Flow A**.

**Postcondition**: `develop` is back in sync with `origin/develop`; the work is safely on a proper branch and merged via PR.
