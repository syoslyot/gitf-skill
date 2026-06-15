# Contributing

## Editing the skill

All behavior lives in `gitf/SKILL.md`. Changes to flows, decision logic, or rules go there.

## Testing changes

Use Claude Code's `/skill-creator` to run evals against your changes:

1. Edit `gitf/SKILL.md`
2. Invoke `/skill-creator` in Claude Code
3. Point it at `evals/evals.json`
4. Compare outputs before/after

## Adding a new eval case

Edit `evals/evals.json` and add a new entry following the existing format. Include:
- A realistic branch state description
- The expected behavior (which flow, what actions)

## Git Flow for this repo

This repo uses the same Git Flow it documents:
- Branch from `develop` for any change
- PR back to `develop`
- Releases go through `release/*` to `main`

Never commit directly to `main` or `develop`.
