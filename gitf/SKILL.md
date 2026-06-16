---
name: gitf
description: Personal Git Flow automation — invoke with /gitf to automatically handle the entire Git Flow lifecycle. Use this skill whenever the user types /gitf or /gitf -v. Detects platform capabilities (GitHub via gh, or pure-local git) and current branch state, then executes the appropriate flow end-to-end: feature/fix to develop, or full release to main. Default /gitf releases without version bump or tag; /gitf -v bumps version and creates a git tag. Fully automatic — lands branches, tags, cleans up, without waiting for confirmation. On GitHub it uses PRs and, if branch protection blocks auto-merge, saves state to .gitf/state.json and resumes on the next /gitf call. With no remote or no gh it falls back to local merges.
---

# /gitf — Personal Git Flow Automation

Fully automatic Git Flow. **Detect capabilities + state → load one flow + one
provider → execute end-to-end without pausing.**

This file is the slim core: bootstrap, detection, routing, state schema, rules.
It contains no flow step details and no platform commands — those live in the
files it tells you to load.

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
ls ~/.claude/skills/gitf/flows/ ~/.claude/skills/gitf/providers/ >/dev/null 2>&1 \
  || echo "GITF_NEEDS_HEAL"
```

If `GITF_NEEDS_HEAL` printed → run `gitf-update.sh` once more to pull the full
tree before proceeding.

Then check whether this project has been configured:

```bash
[ -f .gitf/config ] || echo "GITF_NOT_CONFIGURED"
```

If `GITF_NOT_CONFIGURED` printed → load `INSTALL.md`, run the one-time setup, and
only then continue. If `.gitf/config` already exists, never read `INSTALL.md`.

---

## Step 0: Detect platform capabilities

```bash
bash ~/.claude/skills/gitf/gitf-detect.sh
```

Read the JSON verbatim — do **not** reason about remote URLs yourself.

```json
{"provider":"github|local","needs_login":bool,"has_remote":bool,
 "default_remote":"origin","gh_installed":bool,"gh_logged_in":bool,"platform_config":"auto"}
```

- `needs_login=true` → emit **status-messages: needs-login** and stop. (gh is
  installed but not logged in; the user logs in or sets `platform:local`.)
- Otherwise the chosen `provider` is `github` or `local`. You will load
  `providers/<provider>.md` once a flow is selected.

---

## Step 0.5: Parse flags and check saved state

Flags:
- `/gitf -v` → `VERSION_MODE=true`; `/gitf` → `VERSION_MODE=false`.
  `-v` only affects Flow B. Other flows ignore it.
- `/gitf --skip-review` → `SKIP_REVIEW=true`; skips the code-review gate (B-4 /
  C-2) for this run only. Default `false`.

State is a branch-keyed map (written by **either** provider — github for
PR-merge pauses, both providers for the code-review pause). Look it up by the
current branch (cache hit / miss):

```bash
current=$(git branch --show-current)
entry=$(bash ~/.claude/skills/gitf/gitf-state.sh get "$current")
```

- **`entry` non-empty** → read its `pause_sha` and validate identity:

  ```bash
  bash ~/.claude/skills/gitf/gitf-state.sh valid "$current" "<pause_sha>"
  ```

  - exit 0 → **CACHE HIT**: load `flows/resume.md` (and `providers/<provider>.md`)
    and resume this entry. Do not re-derive anything from git/gh beyond what
    resume needs.
  - exit 1 → reused branch name (the paused tip is no longer an ancestor); treat
    as **CACHE MISS**.

- **`entry` empty** → **CACHE MISS**: run detection from Step 1; the chosen flow
  executes in idempotent mode (probe git/gh before each action; see each flow).

---

## Step 1: Detect current branch state

Run in parallel:

```bash
git branch --show-current
git status --short
git log develop..HEAD --oneline
git log main..develop --oneline
```

---

## Decision Tree → which flow to load

```
Step 0.5 cache hit?               → flows/resume.md

On feature/* or fix/*             → flows/flow-a.md
On hotfix/*                       → flows/flow-c.md
On release/*                      → flows/flow-b.md   (resume mid-release)

On develop
├── uncommitted changes           → flows/flow-d.md  (Case 1) → flow-a
├── commits ahead of origin/dev   → flows/flow-d.md  (Case 2) → flow-a
├── develop ahead of main         → flows/flow-b.md  (full release)
└── develop == main               → status-messages: nothing-to-do

On main                           → status-messages: warn-on-main
```

**Routing**: once a flow is chosen, load `flows/<chosen>.md` and
`providers/<provider>.md`. Additionally load `flows/status-messages.md` when you
need to emit a message, and `flows/code-review-gate.md` when Flow B / Flow C
reaches its code-review step (B-4 / C-2). Load nothing else.

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

## State file schema (v2)

`.gitf/state.json` is a branch-keyed map. Each paused flow is one entry; flows on
different branches are independent. Read/write it **only** via `gitf-state.sh`
(get/put/del/list/valid) — never hand-edit the JSON.

```json
{
  "version": 2,
  "flows": {
    "feature/auth-jwt": {
      "flow": "A", "step": "awaiting_merge", "pr_number": 3,
      "source_branch": "feature/auth-jwt", "target_branch": "develop",
      "release_branch": null, "version": null, "version_mode": false,
      "main_pr_merged": false, "develop_pr_number": null,
      "pause_sha": "a1b2c3d"
    }
  }
}
```

An entry is written on pause — a PR that cannot be auto-merged (github), or the
code-review gate stopping with unresolved findings (either provider). The entry
is deleted when its flow completes, when its PR was closed without merge, or when
its branch is cleaned up.

| Field | Description |
|-------|-------------|
| `flow` | A / B / C |
| `step` | `awaiting_merge` / `awaiting_merge_to_main` / `awaiting_merge_to_develop` / `awaiting_code_review` |
| `pr_number` | the PR currently waiting (null for `awaiting_code_review`) |
| `source_branch` | branch that was landed |
| `target_branch` | base branch of the waiting PR |
| `release_branch` | (B/C) the release/* or (C) hotfix/* branch under review/merge — also the branch the `awaiting_code_review` resume re-reviews |
| `version` | (B/C, version mode) version string |
| `version_mode` | whether `-v` was passed — drives tagging on resume |
| `main_pr_merged` | (B) whether release→main is done |
| `develop_pr_number` | (B) back-merge PR number once created |
| `pause_sha` | branch tip at pause time; resume trusts the entry only if this is an ancestor of the current branch |

---

## Rules

- **This skill runs ONLY when the user explicitly types `/gitf` or `/gitf -v`.**
  Never invoke it automatically. Do not write instructions into any project's
  CLAUDE.md, AGENTS.md, or similar that would auto-trigger it.
- Never commit directly to `develop` or `main`.
- `feature/*` and `fix/*` always branch from develop, never from main.
- Merges are always merge commits (`--merge` / `--no-ff`), never squash/rebase.
- **[version only]** Tag immediately after the release lands on main, before the
  back-merge to develop.
- When back-merging a release/hotfix on github, pass `--head <branch>` (the
  current branch may be `main`).
- Delete release/feature/fix branches after the flow completes (local + remote).
- github provider: check `mergeStateStatus` before `gh pr merge` — never merge
  blindly. Drop a branch's state entry (via `gitf-state.sh del`) only when its
  flow is fully complete.
- **Ambiguity halts.** On any ambiguous or unexpected state — a merge conflict,
  or contradictory probe results — stop and report. Never guess or auto-recover.
- **In-flight ordering** (cache-miss): starting a release (B-0) halts if any
  unfinished `release/*` or `hotfix/*` exists; a hotfix (C-0) halts only on
  another unfinished `hotfix/*`. Resuming a suspended branch (cache hit) is never
  blocked by this guard.
- State lives in `.gitf/state.json` (v2 map) accessed only via `gitf-state.sh`.
  A paused flow's entry is keyed by its owning branch and carries `pause_sha`.
- Code-review gate (B-4 / C-2) runs on the local branch before landing on main,
  so it pauses on either provider. The reviewer tools come from `.gitf/config`;
  judge their output — do not hardcode an "empty == pass" rule. `--skip-review`
  bypasses it.
- If `gh` errors or a PR creation fails, stop and report clearly.
- Re-run detection every invocation — never assume a cached platform.
