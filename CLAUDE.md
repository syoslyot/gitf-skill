# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this project is

A Claude Code skill (`/gitf`) that automates the full Git Flow lifecycle. Users install it once and invoke `/gitf` to handle feature → develop merges, full releases to main, version bumping, tagging, and cleanup — all without manual steps.

## Installation (for end users)

```bash
cp -r gitf/ ~/.claude/skills/gitf/
```

## Project structure

The skill is multi-file and loaded on demand:

- `gitf/SKILL.md` — slim core: bootstrap/self-heal, survey call, topology decision tree, routing, operation-contract interface, rules. Always loaded.
- `gitf/gitf-survey.sh` — single FACTS script: platform + branch/topology + worktree facts from the live git DAG → single-line JSON.
- `gitf/gitf-update.sh` — self-updater (tarball sync of the whole `gitf/` tree + self-heal).
- `gitf/providers/` — one file per platform implementing the operation contract (`github.md`, `local.md`, `README.md`). Exactly one is loaded per run.
- `gitf/flows/` — `flow-a|b|c|d.md`, `code-review-gate.md`, `status-messages.md`. Exactly one flow is loaded per run.
- `gitf/tests/test-survey.sh` — capability + topology + worktree mock unit tests for the survey script.
- `evals/evals.json` — test cases for iterating on the skill via `/skill-creator`.

## Developing the skill

Behavior is split by concern: platform-agnostic Git Flow steps live in `flows/` (coarse verbs only), platform commands live in `providers/`, and the glue lives in `SKILL.md`. There are no build steps.

Run the survey tests directly: `bash gitf/tests/test-survey.sh` (pure-local, no network, exit 0 = green).

To test skill behavior, use `/skill-creator` in Claude Code — it reads `evals/evals.json` and runs subagents against the skill. Workspace outputs go in `gitf-workspace/` (gitignored).

## Git Flow for this repo

Branch rules:
- `main` — stable only
- `develop` — integration branch
- `feature/*` / `fix/*` — branch from develop, PR back to develop
- No direct commits to `main` or `develop`

**DO NOT execute any Git Flow operations (push, PR, merge, tag, branch) on your own.** Wait until the user explicitly types `/gitf` or `/gitf -v`. Until then, only read and edit files.
