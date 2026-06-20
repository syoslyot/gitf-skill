# Decision Tree Specification

This document defines the authoritative decision logic for `/gitf`. The skill must
follow this exactly. `gitf/SKILL.md` is the executable form of this spec; when the
two disagree, `SKILL.md` wins and this document should be corrected.

> **Stateless by design.** `/gitf` keeps **no** `.gitf/config` and **no**
> `.gitf/state.json`. Every fact is read fresh from the live git DAG (and `gh`)
> on each invocation; every pause point is re-derived, never stored. There is no
> cache, no first-run setup, and no resume file. Earlier versions had all three —
> they were removed in v2.0.0.

## Facts: the single source of truth

`/gitf` first runs `gitf/gitf-survey.sh`, which reads the live git DAG and
`git worktree list` and emits **one line of JSON**. The skill reads this verbatim
and never re-derives a fact itself:

```json
{"platform":{"provider":"github|local","needs_login":bool,"has_remote":bool,"default_remote":"origin|null"},
 "branch":{"current":"<name>","head":"<sha>","dirty":bool},
 "topology":{"is_develop":bool,"is_main":bool,"gitf_branch":"release|hotfix|null",
   "ahead_of_develop":int,"merged_into_develop":bool,"ahead_of_origin":int,"develop_ahead_of_main":int},
 "worktrees":{"current_path":"<abs>","main_path":"<abs>","current_is_linked":bool,
   "develop_at":"<abs|null>","main_at":"<abs|null>"}}
```

### Platform capability rules (computed inside the survey)

Capability is a question of **what `gh` can do**, not what the remote URL looks
like (a logged-in `gh` routes to the correct host on its own, so GitHub
Enterprise needs no special handling):

```
1. no remote                      → provider=local
2. gh installed AND logged in     → provider=github
3. gh installed, NOT logged in    → provider=local, needs_login=true (stop, prompt)
4. gh not installed               → provider=local
```

`provider` selects which `providers/<provider>.md` is loaded once a flow is
chosen. The `/gitf --local` flag forces `provider=local` for the run regardless
of the surveyed value — this replaces the removed per-project platform override.

## Flags (Step 0.5)

```
-v             VERSION_MODE=true — bump version + tag (Flow B/C tagging only)
--skip-review  SKIP_REVIEW=true  — skip the code-review gate (B-4 / C-2) this run
--local        force provider=local for this run
```

There is no saved state to consult. Every pause point — a blocked GitHub PR, an
unfinished release, an unresolved code review — is re-derived from `gh` and the
git graph by the chosen flow. Flows run **idempotently**: they probe before each
action and skip steps already done.

## Decision rules (routed from FACTS, evaluated in order)

```
1. topology.is_main
   → STOP: warn user not to work directly on main

2. topology.is_develop
   2a. branch.dirty OR topology.ahead_of_origin > 0
       → FLOW D (rescue) → FLOW A
   2b. topology.develop_ahead_of_main > 0
       → FLOW B (full release)
   2c. else
       → STOP: "develop and main are in sync, nothing to release"

3. topology.gitf_branch == "release"
   → FLOW B (continue an in-progress release)

4. topology.gitf_branch == "hotfix"
   → FLOW C

5. else — a TOPIC branch (ANY name that is not main/develop/release/hotfix)
   5a. topology.ahead_of_develop > 0
       → FLOW A (land on develop)
   5b. topology.merged_into_develop AND (branch still exists OR worktree present)
       → FLOW A in CLEANUP-only mode (the land already happened; just clean up)
   5c. else
       → STOP: "nothing to do"
```

**Topic branches are classified by topology, never by name prefix.** A branch
called `spike-foo` with commits ahead of develop is treated exactly like
`feature/foo`. The `feature/*` / `fix/*` convention is a recommendation, not a
routing requirement.

## Ambiguity resolution

- On develop, if both 2a conditions hold (dirty working tree **and** unpushed
  commits), Flow D handles both in one pass — the dirty changes and the rogue
  commits move onto the inferred branch together.
- If a version bump type is ambiguous between patch and minor, default to minor.
  `BREAKING CHANGE` → major, but confirm with the user first.
- **Halt on ambiguity.** On any ambiguous or unexpected state — a merge conflict,
  contradictory probe results, a dirty worktree blocking a cleanup — stop and
  report. Never guess or auto-recover. Idempotent probing exists to safely skip
  completed steps, not to rescue an unknown state.
- **In-flight production-change ordering.** A `release` must wait for every
  unfinished production change: starting a release from `develop` halts if any
  `release/*` **or** `hotfix/*` branch has commits not in `main` (you do not ship
  a release while a bug is being hotfixed, nor open two releases at once). A
  `hotfix` is highest priority and waits only for **another** unfinished
  `hotfix/*`; it does not halt for an in-flight release (that release will wait
  for the hotfix). This guard is derived from `git branch` + `git log`, not from
  stored state, so it never blocks resuming a branch you already have checked
  out — only starting a brand-new flow.

## Preconditions

Before executing any flow, verify:

- The survey ran and produced facts. If `platform.needs_login=true`, stop and
  emit the `needs-login` message instead of running a flow.
- The target base branch (`develop` or `main`) exists locally — and on the
  remote too when `has_remote=true`.

The `github` provider additionally requires `gh` authenticated (guaranteed by
`provider=github`). The `local` provider has no remote/`gh` precondition.

If any precondition fails: stop and report clearly.
