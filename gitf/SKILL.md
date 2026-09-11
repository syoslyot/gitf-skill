---
name: gitf
description: "Personal Git Flow automation — invoke with /gitf to automatically handle the entire Git Flow lifecycle. Use this skill whenever the user types /gitf or /gitf -v. Detects platform capabilities (GitHub via gh, or pure-local git) and routes by git topology, then executes the appropriate flow end-to-end: any topic branch to develop, or full release to main. Default /gitf releases without version bump or tag; /gitf -v bumps version and creates a git tag. Fully automatic — lands branches, tags, cleans up, without waiting for confirmation. Works under git worktrees. On GitHub it uses PRs and, if branch protection blocks auto-merge, it writes no state — the next /gitf call re-derives position from the git graph and gh and resumes. With no remote or no gh (or /gitf --local) it falls back to local merges."
---

# /gitf — Personal Git Flow Automation

Fully automatic Git Flow. **Detect capabilities + state → load one flow + one
provider → execute end-to-end without pausing.**

This file is the slim core: bootstrap, the facts survey, routing, rules. It
contains no flow step details and no platform commands — those live in the files
it tells you to load.

---

## Step -1: Bootstrap / self-heal (ALWAYS run first)

```bash
bash ~/.claude/skills/gitf/gitf-update.sh
```

If output starts with `gitf updated:` → tell the user in one line, continue.
Otherwise continue silently.

Then verify the multi-file layout exists (an old single-file install won't have
it):

```bash
ls ~/.claude/skills/gitf/flows/ ~/.claude/skills/gitf/providers/ \
   ~/.claude/skills/gitf/gitf-survey.sh >/dev/null 2>&1 || echo "GITF_NEEDS_HEAL"
```

If `GITF_NEEDS_HEAL` printed → run `gitf-update.sh` once more to pull the full
tree before proceeding.

---

## Step 0: Gather facts (single source of truth)

```bash
bash ~/.claude/skills/gitf/gitf-survey.sh
```

Read the JSON verbatim — do **not** re-derive any fact yourself.

```json
{"platform":{"provider":"github|local","needs_login":bool,"has_remote":bool,"default_remote":"origin|null"},
 "branch":{"current":"<name>","head":"<sha>","dirty":bool},
 "topology":{"model":"gitflow|trunk","integration":"develop|main","is_integration":bool,
   "is_develop":bool,"is_main":bool,"gitf_branch":"release|hotfix|null",
   "ahead_of_integration":int,"merged_into_integration":bool,"ahead_of_origin":int,"develop_ahead_of_main":int},
 "worktrees":{"current_path":"<abs>","main_path":"<abs>","current_is_linked":bool,
   "develop_at":"<abs|null>","main_at":"<abs|null>"}}
```

- `topology.model` is derived from whether a `develop` branch exists. `gitflow` =
  two trunks, topic work lands on `develop`. `trunk` = single trunk, topic work
  lands on `main`. `topology.integration` names that branch; **every flow targets
  it, never a hardcoded `develop`.** `is_integration` is true when the current
  branch IS it — so `develop` in a gitflow repo and `main` in a trunk repo route
  through the same branch of the tree.
- `platform.needs_login=true` → emit **status-messages: needs-login** and stop
  (gh installed but not logged in; the user logs in, or passes `/gitf --local`).
- `platform.provider` selects which `providers/<provider>.md` you load once a flow
  is chosen. `/gitf --local` forces `provider=local` for this run regardless of
  the surveyed provider.

---

## Step 0.5: Parse flags

- `/gitf -v` → `VERSION_MODE=true`; `/gitf` → `VERSION_MODE=false`. `-v` affects
  Flow B/C tagging in a gitflow repo, and Flow A's tagging step in a trunk repo.
- `/gitf --skip-review` → `SKIP_REVIEW=true`; skips the code-review gate for this
  run only — B-4 / C-2 under gitflow, and Flow A step 1 on a trunk repo with `-v`.
- `/gitf --local` → force the `local` provider for this run (override a GitHub
  remote). Replaces the removed per-project platform override.

There is no saved state to consult: every pause point (a blocked GitHub PR, an
unfinished release, an unresolved review) is re-derived from `gh` and the git
graph by the chosen flow. Flows run idempotently — they probe before each action.

---

## Decision Tree → which flow to load (routes from FACTS)

```
topology.model == "unknown"                   → status-messages: unknown-model, STOP
                                                 (neither develop nor an identifiable
                                                  trunk — never guess a base)

topology.is_integration:                     # develop (gitflow) or main (trunk)
  branch.dirty                                → flows/flow-d.md → flow-a
  model=="gitflow" && ahead_of_origin>0       → flows/flow-d.md → flow-a
  model=="trunk"   && ahead_of_origin>0       → PUBLISH <integration>, then continue
                                                 down this list. Direct commits to a
                                                 single trunk are how the model works;
                                                 they are not rogue and Flow D must not
                                                 hard-reset them.
  topology.develop_ahead_of_main>0            → flows/flow-b.md  (full release; gitflow only)
  else                                        → status-messages: nothing-to-do
                                                 (trunk → nothing-to-do-trunk)

topology.is_main                              → status-messages: warn-on-main
                                                 (only reachable in gitflow; in a
                                                  trunk repo main is the integration
                                                  branch and is matched above)

topology.gitf_branch == "release"             → flows/flow-b.md  (continue release)
topology.gitf_branch == "hotfix"              → flows/flow-c.md
                                                 (the survey only sets gitf_branch under
                                                  gitflow, so these never fire on a trunk
                                                  repo — a branch named release/* there is
                                                  an ordinary topic branch)

else  (TOPIC branch — any name; not the integration branch/main/release/hotfix):
  topology.ahead_of_integration>0             → flows/flow-a.md
  topology.merged_into_integration
    && (branch still exists || worktree present) → flows/flow-a.md (CLEANUP only)
  else                                        → status-messages: nothing-to-do
```

**Routing**: load `flows/<chosen>.md` and `providers/<provider>.md`. Additionally
load `flows/status-messages.md` to emit a message, and `flows/code-review-gate.md`
when Flow B/C reaches B-4 / C-2. Load nothing else. Topic branches are classified
by topology, never by name prefix.

---

## Operation contract (interface)

Flows speak these coarse verbs; the loaded provider implements them.

| Verb | Meaning |
|------|---------|
| `LAND base head [keep-branch]` | get commits on `head` into `base` |
| `PUBLISH branch` | make branch visible on the remote (if any) |
| `SYNC branch` | bring local branch up to date with remote (if any) |
| `TAG version` | annotated tag `v<version>`, publish if remote exists |
| `CLEANUP branch` | delete branch locally and remotely (if applicable) |

`LAND` is the only verb that differs structurally by platform (github = async,
blockable PR; local = synchronous `--no-ff` merge).

---

## Rules

- **This skill runs ONLY when the user explicitly types `/gitf` or `/gitf -v`.**
  Never invoke it automatically. Do not write instructions into any project's
  CLAUDE.md, AGENTS.md, or similar that would auto-trigger it.
- Never commit directly to the integration branch or `main`.
- `feature/*` and `fix/*` always branch from `topology.integration`. In a gitflow
  repo that is `develop` and never `main`; in a trunk repo `main` is the only trunk.
- **Trunk repos have no Flow B or Flow C.** There is no develop→main promotion to
  make and no separate production line to hotfix — landing on `main` IS the release.
  `-v` therefore bumps and tags at the end of Flow A (see flows/flow-a.md).
- Merges are always merge commits (`--merge` / `--no-ff`), never squash/rebase.
- **[version only]** Tag immediately after the release lands on main, before the
  back-merge to develop.
- When back-merging a release/hotfix on github, pass `--head <branch>` (the
  current branch may be `main`).
- Delete release/feature/fix branches after the flow completes (local + remote).
- github provider: check `mergeStateStatus` before `gh pr merge` — never merge
  blindly.
- **Ambiguity halts.** On any ambiguous or unexpected state — a merge conflict,
  or contradictory probe results — stop and report. Never guess or auto-recover.
- **In-flight ordering**: starting a release (B-0) halts if any unfinished
  `release/*` or `hotfix/*` exists; a hotfix (C-0) halts only on another
  unfinished `hotfix/*`. Derived from git branches, not stored state.
- Code-review gate (B-4 / C-2) runs on the local branch before landing on main,
  so it pauses on either provider. The reviewer tools are detected live (see
  code-review-gate.md); judge their output — do not hardcode an "empty == pass"
  rule. `--skip-review` bypasses it.
- If `gh` errors or a PR creation fails, stop and report clearly.
- Re-run detection every invocation — never assume a cached platform.
