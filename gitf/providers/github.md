# Provider: github

Active when `gitf-detect.sh` reports `"provider":"github"` (gh installed and
logged in). All merges are **merge commits** (`--merge`). `gh` routes to the
correct host on its own — GitHub Enterprise works with no special handling.

This is the only provider that can block. When a PR cannot be auto-merged the
flow saves a state entry (keyed by branch) and resumes later via `resume.md`.

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

**Idempotency probe (cache-miss runs only).** Before `gh pr create`, check for an
existing PR for this exact head→base:

```bash
gh pr list --head <head> --base <base> --state all \
  --json number,state,mergeStateStatus
```

- an `OPEN` PR exists → skip `gh pr create`; reuse that PR number and check its
  `mergeStateStatus` (same as resume).
- a `MERGED` PR exists → this land already happened; skip to the next flow step.
- none → create the PR normally.

On a **cache hit** this probe is skipped — the entry already names the PR.

Decide from `mergeStateStatus`:

| `mergeStateStatus` | Action |
|--------------------|--------|
| `CLEAN` | merge now |
| `BLOCKED` | signal blocked → **status-messages: blocked-review** |
| `UNSTABLE` | signal blocked → **status-messages: blocked-ci-failed** |
| `UNKNOWN` / pending | signal blocked → **status-messages: blocked-ci-running** |

Merge (when `CLEAN`):

```bash
# default: delete the source branch after merge
gh pr merge <number> --merge --delete-branch
# with `keep-branch` (used for release branches still needed for back-merge):
gh pr merge <number> --merge
```

`keep-branch` is passed by flows that still need `head` after this LAND
(e.g. a release branch that must also back-merge into develop).

When blocked, report the blocking `mergeStateStatus` and the PR number back to
the flow. **The flow writes the state entry** (keyed by its branch, via
`gitf-state.sh put` — see flow-a/b/c), then emits the matching `blocked-*`
status message and stops. The provider itself does not touch `.gitf/state.json`.

## PUBLISH branch

```bash
git push -u origin <branch>
```

## SYNC branch

```bash
git checkout <branch> && git pull origin <branch>
```

## TAG version

Idempotency (cache-miss runs): skip if the tag already exists
(`git tag -l v<version>` is non-empty).

```bash
git tag -a v<version> -m "v<version>"
git push origin v<version>
```

## CLEANUP branch

```bash
git push origin --delete <branch>
git checkout develop && git pull origin develop
git branch -d <branch> 2>/dev/null || true
# Hygiene: drop this branch's state entry so a future same-named branch
# can never get a false cache hit.
bash ~/.claude/skills/gitf/gitf-state.sh del "<branch>"
```
