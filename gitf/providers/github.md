# Provider: github

Active when the survey reports `platform.provider` = `github` (gh installed and
logged in). All merges are **merge commits** (`--merge`). `gh` routes to the
correct host on its own — GitHub Enterprise works with no special handling.

This is the only provider that can block. When a PR cannot be auto-merged the
flow writes **no state**, emits a `blocked-*` message and stops; the next `/gitf`
re-locates the PR via `gh pr list --head` and resumes from the graph.

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

**Idempotency probe.** Before `gh pr create`, check for an existing PR for this
exact head→base:

```bash
gh pr list --head <head> --base <base> --state all \
  --json number,state,mergeStateStatus
```

- an `OPEN` PR exists → skip `gh pr create`; reuse that PR number and check its
  `mergeStateStatus`.
- a `MERGED` PR exists → this land already happened; skip to the next flow step.
- a `CLOSED`-unmerged PR → treat as a fresh start; create the PR.
- none → create the PR normally.

This probe is how a re-run re-locates a previously blocked PR — there is no saved
state to consult.

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

When blocked, report the blocking `mergeStateStatus` and the PR number to the
flow, emit the matching `blocked-*` status message, and stop. **No state is
written.** On the next `/gitf`, the flow re-locates this PR with
`gh pr list --head <head> --base <base> --state all --json number,state,mergeStateStatus`
and continues from the graph: an `OPEN` PR is re-checked, a `MERGED` PR advances
to the next step, a `CLOSED`-unmerged PR is treated as a fresh start.

## PUBLISH branch

```bash
git push -u origin <branch>
```

## SYNC branch

```bash
git checkout <branch> && git pull origin <branch>
```

## TAG version

Idempotency (re-run): skip if the tag already exists
(`git tag -l v<version>` is non-empty).

```bash
git tag -a v<version> -m "v<version>"
git push origin v<version>
```

## CLEANUP branch

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
