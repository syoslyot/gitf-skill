# Decision Tree Specification

This document defines the authoritative decision logic for `/gitf`. The skill must follow this exactly.

## Platform detection (before state detection)

`/gitf` first runs `gitf/gitf-detect.sh`, which reports platform **capability**
(not remote-URL shape) as single-line JSON:

```
provider     = github | local
needs_login  = gh installed but not logged in
has_remote   = repo has any remote
```

Capability rules (evaluated in order, `platform_config=auto`):

```
1. no remote                      → provider=local
2. gh installed AND logged in     → provider=github
3. gh installed, NOT logged in    → provider=local, needs_login=true (stop, prompt)
4. gh not installed               → provider=local
```

`.gitf/config` `{"platform":"github|local",...}` overrides the auto result, and
also carries `reviewers` (the ordered code-review tools). The chosen provider
determines how the coarse verbs (`LAND`/`PUBLISH`/`SYNC`/`TAG`/`CLEANUP`) are
carried out. `.gitf/state.json` is a **v2 branch-keyed map**
(`{"version":2,"flows":{"<branch>":{...}}}`) accessed only via `gitf-state.sh`;
each entry records one paused flow: a github PR that cannot auto-merge, or the
code-review gate (B-4 / C-2) stopping with unresolved findings — the latter
pauses on **either** provider, since the review runs on the local branch before
landing. Entries are independent, so multiple branches can be suspended at once.

## State detection

Before any decision, collect:

```
current_branch  = git branch --show-current
status          = git status --short
ahead_of_develop = git log develop..HEAD --oneline   (commits on HEAD not in develop)
ahead_of_main    = git log main..develop --oneline   (commits in develop not in main)
```

## State lookup (Step 0.5, before the decision rules)

Look up the current branch's entry and validate identity:

```
entry = gitf-state.sh get <current_branch>
entry non-empty AND gitf-state.sh valid <current_branch> <entry.pause_sha> (exit 0)
   → CACHE HIT  → FLOW RESUME (trust the entry; do not re-derive)
otherwise (no entry, or pause_sha no longer an ancestor → reused name)
   → CACHE MISS → run the decision rules below; the chosen flow runs in
                  idempotent mode (probe git/gh before each action, halt on
                  ambiguity).
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
- **Halt on ambiguity.** On any ambiguous or unexpected state during a cache-miss
  rebuild — a merge conflict, or contradictory probe results — stop and report.
  Never guess or auto-recover. Idempotent probing exists to safely skip completed
  steps, not to rescue an unknown state.
- **In-flight production-change ordering** (cache-miss B-0 / C-0). A `release` must
  wait for every unfinished production change: starting a release from `develop`
  halts if any `release/*` **or** `hotfix/*` branch has commits not in `main`
  (you do not ship a release while a known bug is being hotfixed, nor open two
  releases at once). A `hotfix` is highest priority and waits only for **another**
  unfinished `hotfix/*`; it does not halt for an in-flight release (that release
  will wait for the hotfix). A legitimately suspended branch resumes via its own
  cache hit, so this guard never blocks resuming — only starting a new flow.

## Preconditions

Before executing any flow, verify:
- Platform detection succeeded (see above). If `needs_login=true`, stop and emit
  the `needs-login` message instead of running a flow.
- The target base branch (`develop` or `main`) exists locally — and on the
  remote too when `has_remote=true`.

The `github` provider additionally requires `gh` authenticated (guaranteed by
`provider=github`). The `local` provider has no remote/`gh` precondition.

If any precondition fails: stop and report clearly.
