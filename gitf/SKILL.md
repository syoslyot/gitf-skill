---
name: gitf
description: "Personal Git Flow automation — invoke with /gitf to automatically handle the entire Git Flow lifecycle. Use this skill whenever the user types /gitf or /gitf -v. Detects platform capabilities (GitHub via gh, or pure-local git) and routes by git topology, then executes the appropriate flow end-to-end: any topic branch to develop, or full release to main. Strict two-trunk Git Flow: a repo without develop gets one created from main — topic work never lands on main. Default /gitf releases without version bump or tag; /gitf -v bumps version and creates a git tag. Fully automatic — lands branches, tags, cleans up, without waiting for confirmation. Works under git worktrees. On GitHub it uses PRs and, if branch protection blocks auto-merge, it writes no state — the next /gitf call re-derives position from the git graph and gh and resumes. With no remote or no gh (or /gitf --local) it falls back to local merges."
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
 "topology":{"develop_ref":"<ref>|null","main_ref":"<ref>|null","is_develop":bool,"is_main":bool,
   "gitf_branch":"release|hotfix|null","ahead_of_develop":int,"merged_into_develop":bool,
   "ahead_of_origin":int,"develop_ahead_of_main":int},
 "worktrees":{"current_path":"<abs>","main_path":"<abs>","current_is_linked":bool,
   "develop_at":"<abs|null>","main_at":"<abs|null>"}}
```

- `topology.develop_ref` / `main_ref` are those branches resolved to something
  `rev-list` can use — the local branch when it exists, otherwise a remote-tracking
  ref such as `origin/develop` (a fresh clone has no local `develop`). `null` means
  the branch exists neither locally nor on a fetched remote. **Providers must use
  the `*_ref` value for any git command that resolves a revision**, and the plain
  name for branch operations and messages.
- Git Flow always has two trunks. There is no single-trunk mode: a repo without
  `develop` is bootstrapped (Step 0.7), never routed onto `main`.
- `platform.needs_login=true` → emit **status-messages: needs-login** and stop
  (gh installed but not logged in; the user logs in, or passes `/gitf --local`).
- `platform.provider` selects which `providers/<provider>.md` you load once a flow
  is chosen. `/gitf --local` forces `provider=local` for this run regardless of
  the surveyed provider.

---

## Step 0.5: Parse flags

- `/gitf -v` → `VERSION_MODE=true`; `/gitf` → `VERSION_MODE=false`. `-v` only
  affects Flow B/C tagging.
- `/gitf --skip-review` → `SKIP_REVIEW=true`; skips the code-review gate (B-4 /
  C-2) for this run only.
- `/gitf --local` → force the `local` provider for this run (override a GitHub
  remote). Replaces the removed per-project platform override.

There is no saved state to consult: every pause point (a blocked GitHub PR, an
unfinished release, an unresolved review) is re-derived from `gh` and the git
graph by the chosen flow. Flows run idempotently — they probe before each action.

---

## Step 0.7: Ensure both trunks exist

```
topology.main_ref == null     → status-messages: no-main, STOP
topology.develop_ref == null  → bootstrap develop (below), then continue
else                          → continue to the decision tree
```

Git Flow is defined by two long-lived branches. A repo with only `main` is not a
different model — it is a Git Flow repo that has not created `develop` yet, the
same state `git flow init` starts from. Landing topic work on `main` instead would
put unreleased work straight onto production and skip Flow B entirely.

**Bootstrap develop.** `<remote>` is `platform.default_remote`.

1. `has_remote=true` → `git fetch <remote> --prune`, then re-run the survey. If
   `develop_ref` is now non-null, develop already existed remotely — skip the
   rest of this step.
2. Pick the base: `<remote>/main` when that ref exists, else `main`.
3. If the base is `<remote>/main` and local `main` exists, check
   `git rev-list --count <remote>/main..main`. Non-zero → **halt** with
   status-messages: no-develop-main-unpublished. Unpublished commits on `main`
   are ambiguous — they may be production fixes or work that belongs on develop
   — so they are neither silently carried into develop nor left behind.
4. Create and publish it (no checkout — the current branch and working tree are
   untouched, so a dirty topic branch is safe):

   ```bash
   git branch --no-track develop <base>
   git push -u <remote> develop          # has_remote=true only
   ```

   When `has_remote=true` but the base had to be local `main` (the remote has no
   `main` yet), also `git push -u <remote> main` — Flow B later lands on the
   remote `main`, so both trunks must be published.

5. Emit status-messages: develop-bootstrapped, re-run the survey, and route from
   the fresh facts.

---

## Decision Tree → which flow to load (routes from FACTS)

```
topology.is_main                              → status-messages: warn-on-main

topology.is_develop:
  branch.dirty || topology.ahead_of_origin>0  → flows/flow-d.md → flow-a
  topology.develop_ahead_of_main>0            → flows/flow-b.md  (full release)
  else                                        → status-messages: nothing-to-do

topology.gitf_branch == "release"             → flows/flow-b.md  (continue release)
topology.gitf_branch == "hotfix"              → flows/flow-c.md

else  (TOPIC branch — any name; not develop/main/release/hotfix):
  topology.ahead_of_develop>0                 → flows/flow-a.md
  topology.merged_into_develop
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
- Never commit directly to `develop` or `main`.
- `feature/*` and `fix/*` always branch from develop, never from main. A repo
  without develop gets one (Step 0.7) — it is never treated as single-trunk.
- **`CLEANUP` never deletes `develop`, `main`, or `master`.** If a flow
  ever reaches `CLEANUP` with one of those, halt and report instead — deleting the
  production branch is not a recoverable mistake, and no correct flow asks for it.
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
