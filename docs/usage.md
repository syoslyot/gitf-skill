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
the release/hotfix branch **before** it lands on `main`. It uses whatever review
tool you selected during first-run setup (stored in `.gitf/config`).

- Clean review → the release continues automatically.
- Issues `/gitf` can fix itself → fixed on the branch, then re-reviewed.
- Issues needing your call → it stops and lists them; fix them and run `/gitf`
  again to continue from where it paused.

Bypass the gate for one run with `/gitf --skip-review`. If no review tool is
configured, the gate is skipped entirely.

## Multiple branches in flight

Each branch keeps its own paused state, so several flows can be suspended at
once. `/gitf` always acts on whichever branch you currently have checked out:
check out a paused branch and run `/gitf` to resume exactly that flow. Resume is
matched by branch name **and** a fingerprint of the tip at pause time, so
deleting a branch and later creating a different one with the same name never
resumes the old flow by mistake. Finished branches have their state cleaned up
automatically; an abandoned branch's leftover state is ignored safely on the
next run.

## First-run setup

The first `/gitf` in a project asks which review tool to use and writes
`.gitf/config` (also added to `.gitignore`). Subsequent runs skip setup.

## Version bump rules

| Change type | Bump |
|-------------|------|
| Bug fixes only | patch (x.y.**Z**) |
| New features | minor (x.**Y**.0) |
| Breaking changes | major (**X**.0.0) — will ask for confirmation |

## Version file detection

Checked in order: `package.json` → `pyproject.toml` → `Cargo.toml` → `VERSION`. The first one found is used. If none exist, a `VERSION` file is created.
