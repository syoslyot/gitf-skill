# Provider: local

Active when `gitf-detect.sh` reports `"provider":"local"` — no remote, or `gh`
unavailable, or `.gitf/config` forces `local`.

There is **no PR and no CI gate**. Landing is a synchronous `--no-ff` merge and
**never blocks**. The only pause under this provider is the code-review pause
(`step=awaiting_code_review`) — when the B-4 / C-2 review gate stops with findings
the AI could not resolve; the gate (a flow, not this provider) writes the state
entry via `gitf-state.sh`. All other steps run straight through with no state and
no resume.

Behavior of `PUBLISH`/`SYNC`/remote cleanup depends on `has_remote`:

- `has_remote=true` (remote exists but gh is unusable) — merge locally, then
  push the updated base branch. No PR is created.
- `has_remote=false` (purely local repo) — everything stays local; push/pull
  are no-ops.

Use `<remote>` = the detector's `default_remote`.

---

## LAND base head [keep-branch]

**Idempotency probe (cache-miss runs only).** If `git log <base>..<head>` is
empty, `<head>` is already merged into `<base>` — skip the merge and proceed to
the next flow step.

```bash
git checkout <base>
git merge --no-ff <head> -m "Merge <head> into <base>"
```

If `has_remote=true`:

```bash
git push <remote> <base>
```

`keep-branch` only affects later CLEANUP; the merge itself is unchanged.
Never blocks — proceed straight to the next flow step.

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

```bash
git checkout develop
git branch -d <branch> 2>/dev/null || true
# has_remote=true: also remove it from the remote
git push <remote> --delete <branch> 2>/dev/null || true
```
