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

## Version bump rules

| Change type | Bump |
|-------------|------|
| Bug fixes only | patch (x.y.**Z**) |
| New features | minor (x.**Y**.0) |
| Breaking changes | major (**X**.0.0) — will ask for confirmation |

## Version file detection

Checked in order: `package.json` → `pyproject.toml` → `Cargo.toml` → `VERSION`. The first one found is used. If none exist, a `VERSION` file is created.
