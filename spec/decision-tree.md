# Decision Tree Specification

This document defines the authoritative decision logic for `/gitf`. The skill must follow this exactly.

## State detection

Before any decision, collect:

```
current_branch  = git branch --show-current
status          = git status --short
ahead_of_develop = git log develop..HEAD --oneline   (commits on HEAD not in develop)
ahead_of_main    = git log main..develop --oneline   (commits in develop not in main)
```

## Decision rules (evaluated in order)

```
1. current_branch matches feature/* or fix/*
   → FLOW A

2. current_branch matches hotfix/*
   → FLOW C

3. current_branch matches release/*
   → FLOW B (resume in-progress release)

4. current_branch == "develop"
   4a. status is non-empty (uncommitted changes)
       → FLOW D, Case 1
   4b. ahead_of_develop is non-empty (commits on develop not yet pushed / rogue commits)
       → FLOW D, Case 2
   4c. ahead_of_main is non-empty (develop has releasable commits)
       → FLOW B
   4d. ahead_of_main is empty
       → STOP: "develop and main are in sync, nothing to release"

5. current_branch == "main"
   → STOP: warn user not to work directly on main
```

## Ambiguity resolution

- If both 4a and 4b are true (uncommitted changes AND rogue commits): treat as 4a (unstaged first)
- If on develop with uncommitted changes that look like an in-progress release bump: ask before proceeding
- If version bump type is ambiguous between patch and minor: default to minor

## Preconditions

Before executing any flow, verify:
- `gh` is installed and authenticated (`gh auth status`)
- The repo has a remote named `origin`
- The target base branch (`develop` or `main`) exists both locally and on remote

If any precondition fails: stop and report clearly.
