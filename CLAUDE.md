# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this project is

A Claude Code skill (`/gitf`) that automates the full Git Flow lifecycle. Users install it once and invoke `/gitf` to handle feature → develop merges, full releases to main, version bumping, tagging, and cleanup — all without manual steps.

## Installation (for end users)

```bash
cp -r gitf/ ~/.claude/skills/gitf/
```

## Project structure

- `gitf/SKILL.md` — the skill itself. This is the only file end users need.
- `evals/evals.json` — test cases for iterating on the skill via `/skill-creator`.

## Developing the skill

All changes to skill behavior happen in `gitf/SKILL.md`. There are no build steps.

To test changes, use `/skill-creator` in Claude Code — it reads `evals/evals.json` and runs subagents against the skill to evaluate outputs. Workspace outputs go in `gitf-workspace/` (gitignored).

## Git Flow for this repo

Standard Git Flow with PR-based merges:
- `main` — stable only
- `develop` — integration branch
- `feature/*` / `fix/*` — branch from develop, PR back to develop
- No direct commits to `main` or `develop`

Use `/gitf` within this repo to execute the workflow.
