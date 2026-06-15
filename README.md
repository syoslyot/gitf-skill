# git-flow-skill

A Claude Code skill that automates the full Git Flow lifecycle with a single command: `/gitf`.

## What it does

Detects your current git state and executes the appropriate flow end-to-end — no confirmation prompts, no manual steps.

| Current state | Action |
|--------------|--------|
| `feature/*` or `fix/*` | Push → PR to develop → merge → pull |
| `hotfix/*` | PR to main → tag → PR to develop → merge → pull |
| `develop` (AI forgot to branch) | Auto-create branch from context → move commits → PR to develop |
| `develop` ahead of main | Full release: branch → bump version → PR to main → tag → PR to develop → clean up |
| `develop` in sync with main | Informs you there's nothing to release |
| `main` | Warns you not to work directly on main |

## Installation

Copy the `gitf/` directory to your Claude Code skills folder:

```bash
cp -r gitf/ ~/.claude/skills/gitf/
```

Then use `/gitf` in any Claude Code session.

## Git Flow reference

This skill follows the standard Vincent Driessen Git Flow:
- `main` — production only, receives merges from `release/*` and `hotfix/*`
- `develop` — integration branch
- `feature/*` — branches from develop, merges back to develop
- `fix/*` — same as feature
- `release/*` — branches from develop, merges to main AND develop
- `hotfix/*` — branches from main, merges to main AND develop

Version bump rules: `fix` → patch, new feature → minor, breaking change → major.

## Merge strategy

All merges use merge commit (not squash or rebase), preserving full branch history.

## Version file detection

Auto-detects: `package.json` → `pyproject.toml` → `Cargo.toml` → `VERSION` (created if none found).
