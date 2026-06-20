# Usage

Type `/gitf` in any Claude Code session. The skill detects your current git state and executes the appropriate flow automatically — no further input needed.

## Scenarios

### Finished a feature or fix

You're on `feature/search-filter` or `fix/login-redirect` and ready to merge:

```
/gitf
```

→ Pushes branch, opens PR to `develop`, merges it, checks out and pulls `develop`.

### Ready to release

You're on `develop`, the branch is clean, and there are commits not yet in `main`:

```
/gitf
```

→ Creates `release/vX.Y.Z`, bumps version, opens PR to `main`, merges, tags, back-merges to `develop`, cleans up release branch.

### Emergency production fix

You're on `hotfix/critical-auth-bypass`:

```
/gitf
```

→ PRs to `main`, merges, tags patch version, PRs to `develop`, cleans up.

### AI forgot to branch (committed to develop by mistake)

You're on `develop` with commits that shouldn't be there:

```
/gitf
```

→ Creates a new branch named from commit content, moves the commits, then runs the feature flow.

## Code review before release

When releasing (Flow B) or hotfixing (Flow C), `/gitf` runs a code-review gate on
the release/hotfix branch **before** it lands on `main`. It detects an available
review tool live each run (preferring `/code-review`, then
`superpowers:requesting-code-review`, then `/review`) — there is no setup and
nothing stored.

- Clean review → the release continues automatically.
- Issues `/gitf` can fix itself → fixed on the branch, then re-reviewed.
- Issues needing your call → it stops and lists them; fix them and run `/gitf`
  again to re-run the gate from the top.

Bypass the gate for one run with `/gitf --skip-review`. If no review tool is
available, the gate is skipped entirely.

## Multiple branches in flight

`/gitf` stores no state, so there is nothing per-branch to keep — yet several
flows can still sit paused at once. `/gitf` always acts on whichever branch you
currently have checked out, and reconstructs where that branch was from the git
graph and the PR's live status on GitHub (`gh pr list --head …`). Check out a
paused branch and run `/gitf` to resume it. Because position is re-derived rather
than remembered, a deleted-then-recreated branch name can never resume a stale
flow by mistake, and an abandoned branch simply has no PR to find.

## No setup, no config

There is no first-run setup and no `.gitf/` config or state file. Everything
`/gitf` needs — platform capability, branch topology, the review tool — is read
fresh from the repo on each run.

## Version bump rules

| Change type | Bump |
|-------------|------|
| Bug fixes only | patch (x.y.**Z**) |
| New features | minor (x.**Y**.0) |
| Breaking changes | major (**X**.0.0) — will ask for confirmation |

## Version file detection

Checked in order: `package.json` → `pyproject.toml` → `Cargo.toml` → `VERSION`. The first one found is used. If none exist, a `VERSION` file is created.
