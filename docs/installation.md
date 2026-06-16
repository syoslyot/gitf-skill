# Installation

## Requirements

- [Claude Code](https://claude.ai/code) (CLI or IDE extension)
- Git repository with a `develop` branch
- [GitHub CLI](https://cli.github.com/) (`gh`), authenticated — **optional**. With
  it, `/gitf` uses PRs (review/CI aware); without it (or with no remote), it falls
  back to synchronous local merges.
- Optional: a code-review skill (e.g. `/code-review`) for the pre-release review
  gate — selected on first run.

## Install

Copy the `gitf/` directory into your Claude Code global skills folder:

```bash
cp -r gitf/ ~/.claude/skills/gitf/
```

Verify it's available:

```bash
ls ~/.claude/skills/gitf/
# SKILL.md
```

## First use

In any Claude Code session, type `/gitf`. The skill appears in the autocomplete
list once installed.

The first run in a project performs a one-time setup: it detects your available
review tools, asks which to use for the pre-release code-review gate, and writes
`.gitf/config` (and adds `.gitf/` to `.gitignore`). Later runs skip setup.

## Uninstall

```bash
rm -rf ~/.claude/skills/gitf/
```
