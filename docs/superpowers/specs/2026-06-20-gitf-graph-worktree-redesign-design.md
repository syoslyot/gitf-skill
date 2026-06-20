# /gitf — Graph-as-Source-of-Truth Redesign (worktree support)

**Date:** 2026-06-20
**Status:** Approved design, pre-implementation
**Scope:** Option C — larger refactor. Behaviour (auto-merge, auto-pull, auto-tag,
auto-cleanup) is unchanged; the architecture beneath it is rebuilt.

---

## 1. Problem

`/gitf` breaks under git worktrees, and the root causes are symptoms of two
older design choices that should be removed entirely, not patched:

1. **Routing by branch-name prefix.** The decision tree keys off `feature/*`,
   `fix/*`, `hotfix/*`, `release/*`. A worktree branch named `issue-42`,
   `42-login`, or `jl/wip` matches no prefix and falls out of the tree —
   undefined behaviour. Engineers name worktree branches freely; the skill must
   not require a prefix on **user-created** topic branches.

2. **Probing state with `git checkout`.** `CLEANUP` runs `git checkout develop`
   and `git branch -d`; the local `LAND` runs `git checkout <base>`. In a
   worktree, `develop`/`main` are checked out elsewhere, so these checkouts fail
   (`already checked out at ...`, `cannot delete branch checked out at ...`), and
   the worktree directory is never removed (no `git worktree remove`) — it leaks.

3. **Self-maintained parallel state** (`.gitf/config`, `.gitf/state.json`) that
   mostly duplicates what git and `gh` already know, adding staleness, a
   `pause_sha` anti-staleness hack, and a one-time `INSTALL.md` setup ceremony.

## 2. Design principle

**The git DAG plus `git worktree list` is the single source of truth.** Two hard
rules follow:

- **Scripts gather deterministic facts and execute git commands; the AI only
  judges genuine ambiguity.** Not "everything in scripts," not "everything in
  prose" — the split is *mechanism vs judgment*.
- **Never store what git can tell us, never guess from names what topology can
  tell us.** Let git's own guards (e.g. `git worktree remove` refusing a dirty
  tree) replace hand-rolled checks.

A fact is "stored" only if it is genuinely external and non-derivable. Under this
test, both `.gitf/config` and `.gitf/state.json` are **eliminated** (§6).

## 3. Architecture

```
                 /gitf   /gitf -v   /gitf --skip-review   /gitf --local
                                       │
                                       ▼
  SKILL.md — orchestrator (reads facts, routes; no platform/prefix reasoning)
     bootstrap → survey → route → load 1 flow + 1 provider → run
        │ ① facts                    │ ③ verbs            │ self-heal
        ▼                            ▼                    ▼
  gitf-survey.sh (FACTS)      flows/*.md (verbs)     gitf-update.sh
   one JSON ← git DAG +              │ ③ verbs (contract)
   git worktree list                ▼
                            providers/{github,local}.md
                             verb impls (worktree-aware)
                                       ▼
                                 git / gh  (via rtk)
```

Only interfaces ① (FACTS) and ③ (VERBS) couple the layers. `flows/` depend on ③
only and never touch git directly; `providers/` implement ③; `SKILL.md` consumes
① and routes. There is no state/config interface anymore.

## 4. Interfaces

### ① FACTS — `gitf-survey.sh` → single JSON (script → AI)

Replaces all prose judgments and `git checkout` probing. One consolidated set of
git calls, one JSON out.

```json
{
  "platform":  {"provider":"github|local","needs_login":bool,
                "has_remote":bool,"default_remote":"origin|null"},
  "branch":    {"current":"<name>","head":"<sha>","dirty":bool},
  "topology":  {"is_develop":bool,"is_main":bool,
                "gitf_branch":"release|hotfix|null",
                "ahead_of_develop":int,"merged_into_develop":bool,
                "ahead_of_origin":int,"develop_ahead_of_main":int},
  "worktrees": {"current_path":"<abs>","main_path":"<abs>",
                "current_is_linked":bool,
                "develop_at":"<abs|null>","main_at":"<abs|null>"}
}
```

`gitf_branch` recognises **gitf's own** release/hotfix branch shape — a closed
loop where gitf both writes and reads the name. This is *not* the banned
behaviour; the ban is on requiring users to prefix *their* topic branches.

### ② VERBS — flow ↔ provider (signatures unchanged; impls worktree-aware)

| Verb | github | local |
|------|--------|-------|
| `LAND base head [keep-branch]` | PR (async, blockable) | `--no-ff` merge **inside develop's worktree** |
| `PUBLISH branch` | `push -u` | `push -u` (no-op without remote) |
| `SYNC branch` | bring local up to remote | same |
| `TAG version` | annotated `v<version>`, push | annotated, push if remote |
| `CLEANUP branch` | worktree remove (no `--force`) → `branch -d` → remote delete → `prune` | same |

### State / config interface — **removed.** (§6)

## 5. Decision tree (routes from FACTS, zero prefixes)

```
is_main                                  → status: warn-on-main
is_develop:
    dirty || ahead_of_origin>0           → flow-d (rescue) → flow-a
    develop_ahead_of_main>0              → flow-b (release)
    else                                 → status: nothing-to-do
gitf_branch == release                   → flow-b (continue, positioned from graph)
gitf_branch == hotfix                    → flow-c
TOPIC branch (any name; not develop/main/gitf_branch):
    ahead_of_develop>0                   → flow-a
    merged_into_develop && worktree/branch still present → flow-a CLEANUP only
    else                                 → status: nothing-to-do
```

`merged_into_develop && present` is the one added branch: re-running `/gitf` after
a merge finishes the cleanup that a prior run could not (e.g. a leaked worktree).

## 6. Eliminating `.gitf/config` and `.gitf/state.json`

### `.gitf/config` — deleted

- `platform: auto` is fully derivable each run (remote present? gh logged in?).
  The only non-derivable case is forcing `local` on a GitHub repo — expressed
  per-invocation via `/gitf --local`, not persisted.
- `reviewers` is detected live (`ls ~/.claude/skills/`, fixed preference order);
  the chosen default need not be remembered. A non-default choice, if ever
  needed, is a flag, not stored config.

Consequence: `INSTALL.md`, the `GITF_NOT_CONFIGURED` bootstrap branch, and the
`.gitignore` setup step all disappear.

### `.gitf/state.json` — deleted

Every former pause point is re-derived on the next invocation:

- **GitHub PR awaiting an out-of-band merge** — `gh pr list --head <branch>
  --state all --json number,state,baseRefName,mergeStateStatus` is the source of
  truth. A deleted-and-recreated branch simply has no open PR, so the `pause_sha`
  anti-staleness hack is no longer needed.
- **Where a release is in its flow** — derived from the graph: on main? tagged?
  is there a develop back-merge PR/merge?
- **Code-review gate stopped on findings** — leaves no git/gh trace, but needs no
  memory: re-running `/gitf` on the release branch re-runs the gate idempotently.
  The bookmark never saved the cost of re-reviewing.
- **`-v` (version_mode) intent on resume** — non-derivable, but the user invokes
  `/gitf` each time, so resume-and-tag is re-expressed as `/gitf -v`.

Result: **zero persistent state.** The `.gitf/` directory is gone. Flows become
fully idempotent and stateless — each run re-locates its position from git + gh
and continues. Cost: one or two `gh` queries per run (resume already did this);
benefit: single source of truth, no staleness, no `pause_sha`, no setup ceremony.

## 7. Worktree handling (sunk into verb impls; flows unchanged)

| Situation | Action | How |
|-----------|--------|-----|
| Branch to clean lives in a worktree | Remove worktree, then delete branch | cd main worktree → `git worktree remove <path>` (**no `--force`**) → `git branch -d` → remote delete → `git worktree prune` |
| Worktree has uncommitted/untracked files | Stop and report (the chosen behaviour) | `git worktree remove` **refuses by itself** → halt; no hand-rolled cleanliness check |
| local `LAND` while develop is checked out in another worktree | Merge inside that worktree | use survey's `develop_at`; if develop has no worktree, create an ephemeral one, merge, then `remove` |

## 8. Situation table (situation → action → how)

**Entry (every `/gitf`)**

| Situation | Action | How |
|-----------|--------|-----|
| Invoked | Self-heal + gather facts | `gitf-update.sh` (silent) → `gitf-survey.sh` emits one JSON. No config check |

**Routing** — see §5.

**Flow A (topic → develop)**

| Situation | Action | How |
|-----------|--------|-----|
| github, PR mergeable | PR → merge → cleanup | `gh pr create` → `mergeStateStatus=CLEAN` → `gh pr merge --merge --delete-branch` → CLEANUP |
| github, PR blocked (BLOCKED/UNSTABLE/pending) | Report, stop | emit blocked message; **no state**; next `/gitf` re-locates via `gh pr list --head` |
| github, re-run with existing OPEN PR | Reuse it | `gh pr list --head <b> --base develop` hit → read `mergeStateStatus` |
| github, re-run, PR MERGED | Skip to cleanup | graph shows merged → CLEANUP |
| github, re-run, PR CLOSED unmerged | Fresh start | no open PR → treat as never done |
| local | merge in develop's worktree → cleanup | survey `develop_at`; `git merge --no-ff` there → push (if remote) → CLEANUP |

**Flow B (release; positioned from graph)**

| Situation (derived) | Action | How |
|---------------------|--------|-----|
| No release branch yet | Create | `checkout -b` gitf-named release branch from develop |
| Release on develop, not on main | Review → land on main | code-review gate → LAND release→main |
| On main, not tagged (when `-v`) | Tag | `TAG <version>` (after main, before back-merge) |
| On main, not back-merged | Back-merge → cleanup | LAND release→develop (`--head release/*`) → CLEANUP → SYNC develop |
| Another unfinished `release/*` exists | Halt | in-flight guard via `git branch --list 'release/*'` |

**Flow C (hotfix)** — same shape as B; branch from main, land on main + develop,
patch-version tag.

**Code-review gate (B / C, before landing on main)**

| Situation | Action | How |
|-----------|--------|-----|
| `--skip-review` | Skip | straight to LAND |
| Reviewer detected | Run, judge | detect installed review skills live (fixed preference) → run → AI judges output |
| Unresolved findings | Stop, report | **no state**; next `/gitf` on the same release branch re-runs the gate (idempotent) |
| No reviewer available | No-op | proceed |

## 9. Non-goals

- No GitLab/Bitbucket native MR/PR (non-GitHub remotes still fall back to local).
- No new mandatory subcommands; `/gitf` stays a single context-sensing command
  with escape-hatch flags (`-v`, `--skip-review`, new `--local`).
- No squash/rebase landing; merges stay merge commits.

## 10. Testing

- Extend `tests/test-detect.sh` into `tests/test-survey.sh`: capability + topology
  + worktree mocks, asserting the JSON contract. Pure-local, no network, exit 0 =
  green.
- Cover worktree CLEANUP order and the dirty-worktree halt (git's own refusal).
- Update `evals/evals.json` with worktree and non-prefixed-branch cases, plus a
  config-less / state-less idempotent-resume case.

## 11. Migration

- Remove `gitf-state.sh`, `INSTALL.md`, the bootstrap config check, and all state
  schema prose from `SKILL.md`.
- Existing repos with a `.gitf/` directory: the new code ignores it; document that
  it can be deleted. No automatic deletion of user files.
