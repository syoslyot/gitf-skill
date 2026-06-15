# Installation

## Requirements

- [Claude Code](https://claude.ai/code) (CLI or IDE extension)
- [GitHub CLI](https://cli.github.com/) (`gh`) — authenticated with your GitHub account
- Git repository with a `develop` branch and GitHub remote

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

In any Claude Code session, type `/gitf`. The skill appears in the autocomplete list once installed.

## Uninstall

```bash
rm -rf ~/.claude/skills/gitf/
```
