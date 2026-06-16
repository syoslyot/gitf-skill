# Provider: github

Active when `gitf-detect.sh` reports `"provider":"github"` (gh installed and
logged in). All merges are **merge commits** (`--merge`). `gh` routes to the
correct host on its own — GitHub Enterprise works with no special handling.

This is the only provider that can block. When a PR cannot be auto-merged it
saves `.git/gitf-state.json` and the flow resumes later via `resume.md`.

---

## LAND base head [keep-branch]

```bash
# 1. Publish the branch
git push -u origin <head>

# 2. Open the PR (title in Conventional Commits form; body summarizes commits)
gh pr create --base <base> --head <head> --title "<title>" --body "<body>"

# 3. Check before merging — never merge blindly
gh pr view <number> --json state,mergeStateStatus,statusCheckRollup
```

Decide from `mergeStateStatus`:

| `mergeStateStatus` | Action |
|--------------------|--------|
| `CLEAN` | merge now |
| `BLOCKED` | save state → **status-messages: blocked-review** |
| `UNSTABLE` | save state → **status-messages: blocked-ci-failed** |
| `UNKNOWN` / pending | save state → **status-messages: blocked-ci-running** |

Merge (when `CLEAN`):

```bash
# default: delete the source branch after merge
gh pr merge <number> --merge --delete-branch
# with `keep-branch` (used for release branches still needed for back-merge):
gh pr merge <number> --merge
```

`keep-branch` is passed by flows that still need `head` after this LAND
(e.g. a release branch that must also back-merge into develop).

When blocked, save `.git/gitf-state.json` per the schema in `SKILL.md`, then
emit the matching `blocked-*` status message and stop.

## PUBLISH branch

```bash
git push -u origin <branch>
```

## SYNC branch

```bash
git checkout <branch> && git pull origin <branch>
```

## TAG version

```bash
git tag -a v<version> -m "v<version>"
git push origin v<version>
```

## CLEANUP branch

```bash
git push origin --delete <branch>
git checkout develop && git pull origin develop
git branch -d <branch> 2>/dev/null || true
```
