# Provider: local

Active when the survey reports `platform.provider` = `local` — no remote, or `gh`
unavailable, or `/gitf --local` forces `local`.

There is **no PR and no CI gate**. Landing is a synchronous `--no-ff` merge and
**never blocks**. The only pause under this provider is the code-review pause —
when the B-4 / C-2 review gate stops with findings the AI could not resolve. No
state is written: re-running `/gitf` on the same release/* or hotfix/* branch
re-enters the gate idempotently. All steps run straight through.

Behavior of `PUBLISH`/`SYNC`/remote cleanup depends on `has_remote`:

- `has_remote=true` (remote exists but gh is unusable) — merge locally, then
  push the updated base branch. No PR is created.
- `has_remote=false` (purely local repo) — everything stays local; push/pull
  are no-ops.

Use `<remote>` = the detector's `default_remote`.

---

## LAND base head [keep-branch]

**Idempotency probe (cache-miss runs only).** If `git log <base>..<head>` is empty,
`<head>` is already merged into `<base>` — skip the merge, go to the next step.

The merge must happen in the worktree that holds `<base>`. Use survey facts:

- If `<base>` is `develop` and `worktrees.develop_at` is non-null → run the merge
  in that path (it may be the current worktree or another one):

  ```bash
  git -C <develop_at> merge --no-ff <head> -m "Merge <head> into <base>"
  ```

- If `<base>` is not checked out in any worktree (its `*_at` is null) → create an
  ephemeral worktree, merge there, then remove it:

  ```bash
  tmp=$(mktemp -d)
  git worktree add "$tmp" <base>
  git -C "$tmp" merge --no-ff <head> -m "Merge <head> into <base>"
  git worktree remove "$tmp"
  ```

If `has_remote=true`, push the base afterward: `git push <remote> <base>`.

`keep-branch` only affects later CLEANUP; the merge itself is unchanged. Never
blocks — proceed straight to the next flow step.

## PUBLISH branch

```bash
# has_remote=true:
git push -u <remote> <branch>
# has_remote=false: no-op
```

## SYNC branch

```bash
# has_remote=true:
git checkout <branch> && git pull <remote> <branch>
# has_remote=false: just `git checkout <branch>`
```

## TAG version

Idempotency (cache-miss runs): skip if the tag already exists
(`git tag -l v<version>` is non-empty).

```bash
git tag -a v<version> -m "v<version>"
# has_remote=true:
git push <remote> v<version>
```

## CLEANUP branch

Delete the branch and, if it lives in a worktree, remove that worktree first.
Never stand in the worktree being removed.

```bash
# 1. If <branch> is checked out in a worktree, remove it (no --force: a dirty
#    tree makes git refuse, which is our intended halt — report and stop).
wt=$(git worktree list --porcelain | awk -v b="refs/heads/<branch>" '
  /^worktree /{p=$2} $0=="branch "b{print p}')
if [ -n "$wt" ]; then
  cd <main_path>            # leave the worktree before removing it
  git worktree remove "$wt" || { echo "GITF_HALT: worktree $wt not clean"; exit 0; }
fi

# 2. Delete the branch (now unblocked) locally + remotely.
git branch -d <branch> 2>/dev/null || true
# has_remote=true:
git push <remote> --delete <branch> 2>/dev/null || true

# 3. Hygiene.
git worktree prune
```

If `git worktree remove` printed `GITF_HALT`, stop the flow and tell the user the
worktree has uncommitted/untracked changes and must be cleaned or removed by hand.
