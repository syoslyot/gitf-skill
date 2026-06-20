# Installation

## Requirements

- [Claude Code](https://claude.ai/code) (CLI or IDE extension)
- Git repository with a `develop` branch
- [GitHub CLI](https://cli.github.com/) (`gh`), authenticated — **optional**. With
  it, `/gitf` uses PRs (review/CI aware); without it (or with no remote), it falls
  back to synchronous local merges.
- Optional: a code-review skill (e.g. `/code-review`) for the pre-release review
  gate — detected live each run, no setup needed.

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

There is no setup step and no config file. `/gitf` reads everything it needs from
the git repo on each run — platform capability, branch topology, and (for the
code-review gate) whichever review tool is available. Just run it.

## Uninstall

```bash
rm -rf ~/.claude/skills/gitf/
```
