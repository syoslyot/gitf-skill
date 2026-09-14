# Status Messages

Post-flow and prompt messages. Flows reference these by name. `blocked-*` and
`pr-closed` apply to the `github` provider only (local never blocks).

### flow-a-done
```
✓ <branch-name> landed on develop.
  develop is ahead of main — run /gitf to release, or /gitf -v to release with a version tag.
```

### flow-b-done (no version)
```
✓ <release-branch> landed on main and develop.
  main and develop are in sync.
```

### flow-b-done (version)
```
✓ Released v<version>
  main and develop are in sync.
```

### flow-c-done
```
✓ Hotfix v<version> applied to main and develop.
  main and develop are in sync.
```

### nothing-to-do
```
develop and main are already in sync — nothing to release.
```

### develop-bootstrapped
```
✓ No develop branch found — created develop from <base> and published it.
  Git Flow needs both trunks: topic branches land on develop, releases promote develop to main.
```

### no-develop-main-unpublished
```
⚠ No develop branch, and local main has <n> commit(s) not on <remote>/main.
  Push main (or move those commits to a feature branch), then run /gitf again —
  develop is created from the published main.
```

### no-main
```
⚠ No `main` branch found (locally or on the remote). gitf follows Git Flow with
  `main` as the production branch — rename or create it, then run /gitf again.
```

### warn-on-main
```
⚠ You're on main — work should happen on feature/* or fix/* branches off develop.
```

### needs-login
```
gh is installed but not logged in. Two options:
  • Run `gh auth login`, then /gitf again — uses PRs (review/CI aware).
  • Run /gitf --local — pure local merges for this run, no PRs.
```

### blocked-review
```
⏸ PR #<n> is waiting for review.
  Once it's approved and merged on GitHub, run /gitf to continue.
  Next: <what happens next>
```

### blocked-ci-failed
```
⏸ PR #<n> — CI failed.
  Fix the failing checks, then run /gitf to continue.
```

### blocked-ci-running
```
⏸ PR #<n> — CI is still running.
  Once all checks pass, run /gitf to continue.
```

### pr-closed
```
PR #<n> was closed without merging.
Run /gitf again to start fresh — position is re-derived from git.
```

### blocked-code-review
```
⏸ Code review found issues I couldn't resolve on <branch>:
  • <finding 1>
  • <finding 2>
  Fix them (or re-run with /gitf --skip-review to bypass), then /gitf to continue.
```
