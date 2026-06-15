# git-flow-skill

> A Claude Code skill that turns Git Flow into a single command.

---

## The problem

Git Flow is a solid branching strategy, but following it consistently is tedious. Even when you know the rules, you still have to remember to:

- Create the right branch from the right base
- Write a meaningful PR title
- Merge in the right order
- Bump the version in the right file
- Tag on the right commit
- Back-merge the version bump back to develop
- Clean up branches in both local and remote

In practice, one of these steps gets skipped. And when you're working with an AI agent, the agent often forgets to branch at all and starts committing directly to `develop`.

---

## The solution

`/gitf` — one command, no decisions.

It detects where you are in the Git Flow lifecycle and executes the appropriate flow end-to-end, automatically. No confirmation prompts. No manual steps.

```
/gitf
```

That's it.

---

## What it handles

| Your current state | What /gitf does |
|-------------------|-----------------|
| On `feature/*` or `fix/*` | Push → PR to develop → merge → pull |
| On `hotfix/*` | PR to main → tag → PR to develop → merge → pull |
| On `develop`, ahead of `main` | Full release: branch → bump version → PR to main → tag → back-merge → clean up |
| On `develop`, AI committed here by mistake | Detects rogue commits, creates a branch from context, moves them over, then proceeds |
| On `develop`, in sync with `main` | Tells you there's nothing to release |
| On `main` | Warns you not to work here directly |

---

## Branch protection aware

If your repo has branch protection rules that require a review or waiting on CI, `/gitf` doesn't fail — it pauses. It saves its current progress to `.git/gitf-state.json` and tells you what's blocking.

Once the review is approved or CI passes, run `/gitf` again. It reads the saved state and picks up exactly where it left off.

---

## Version bump logic

When releasing, `/gitf` reads your commit history since the last release and decides the version bump automatically:

| Commits since last release | Bump |
|---------------------------|------|
| Only `fix:` commits | patch — `1.2.3 → 1.2.4` |
| Any `feat:` commit | minor — `1.2.3 → 1.3.0` |
| `BREAKING CHANGE` in body | major — `1.2.3 → 2.0.0` (asks for confirmation) |

Version file detection is automatic: `package.json` → `pyproject.toml` → `Cargo.toml` → `VERSION`. If none exist, a `VERSION` file is created.

---

## Installation

Copy the `gitf/` directory into your Claude Code global skills folder:

```bash
cp -r gitf/ ~/.claude/skills/gitf/
chmod +x ~/.claude/skills/gitf/gitf-update.sh
```

Then use `/gitf` in any Claude Code session across any project.

### Requirements

- [Claude Code](https://claude.ai/code)
- [GitHub CLI](https://cli.github.com/) (`gh`), authenticated
- A repo with a `develop` branch and a GitHub remote

---

## Automatic updates

Once installed, the skill keeps itself up to date. The first time you use `/gitf` each week, it silently checks this repo for a newer version. If one exists, it downloads and installs it in the background. You'll see a one-line notice; the new version takes effect next session.

No manual update steps needed.

---

## How merges work

All merges use **merge commit** (not squash or rebase). This preserves the full branch history — you can see exactly when a feature branch was created and when it landed.

---

## Git Flow reference

This skill follows the [Vincent Driessen Git Flow](https://nvie.com/posts/a-successful-git-branching-model/) with a PR-based workflow:

```
main       ────●────────────────────────────●──  (production)
               │                            ↑
            release/*               merge + tag
               │                            │
develop    ──●─●──●──●──●──●──●──●──●──────●──  (integration)
             ↑          ↑          ↑
          feature/*  feature/*  feature/*
```

| Branch | Branches from | Merges into |
|--------|--------------|-------------|
| `feature/*` | `develop` | `develop` |
| `fix/*` | `develop` | `develop` |
| `release/*` | `develop` | `main` AND `develop` |
| `hotfix/*` | `main` | `main` AND `develop` |

---

## Contributing

See [CONTRIBUTING.md](.github/CONTRIBUTING.md).

The full behavioral spec lives in [`spec/`](spec/) — start there if you're adding a new flow or changing decision logic.
