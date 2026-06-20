# Architecture & Design

A guide for maintainers and anyone who wants to understand *why* `/gitf` is built
the way it is. For end-user behavior see [usage.md](usage.md); for the exact
decision logic see [`spec/`](../spec/).

---

## Design philosophy

### 1. The git graph is the source of truth — `/gitf` is stateless

`/gitf` keeps **no** config file and **no** state file. There is no `.gitf/`
directory, no `state.json`, no first-run setup. Everything it needs is read fresh
from the live git DAG (and `gh`) on every invocation.

This is a deliberate reversal of an earlier design (≤ v1.x) that persisted a
branch-keyed `state.json` and a `.gitf/config`. That machinery was removed in
v2.0.0 because stored state is a liability:

- **It goes stale.** A saved PR number, a remembered "step", or a cached platform
  can disagree with reality after the user (or GitHub) does something out of band.
  The graph and `gh` never disagree with themselves.
- **It needs migration and invalidation.** The old design carried a `pause_sha`
  fingerprint purely to detect when a reused branch name had invalidated an entry.
  None of that exists when nothing is stored.
- **It complicates resume.** Resume is now just "run `/gitf` again": the flow
  re-derives its position by probing the graph and `gh pr list --head <branch>`.

The cost is that a paused flow re-probes on each run instead of reading a cursor.
For a tool that runs a handful of times a day, that cost is negligible and the
correctness win is large.

### 2. Three layers, split by concern

| Layer | Lives in | Knows about |
|-------|----------|-------------|
| **Glue** | `gitf/SKILL.md` | bootstrap, the facts survey, the decision tree, routing, the verb contract, global rules |
| **Flows** | `gitf/flows/` | platform-agnostic Git Flow steps, written against *coarse verbs* only |
| **Providers** | `gitf/providers/` | how each coarse verb is actually executed on a platform |

A flow never contains a `gh` or `git merge` command — it says `LAND base=main
head=<release>`. A provider never contains Git Flow policy — it only knows how to
`LAND`. This keeps the Git Flow logic written once, regardless of platform, and
keeps platform differences quarantined to one small file each.

### 3. Progressive disclosure

`SKILL.md` is the slim always-loaded core. Exactly **one** flow file and **one**
provider file are loaded per run, plus `status-messages.md` (to emit a message)
and `code-review-gate.md` (only when a release/hotfix reaches its gate). Nothing
else is read. This keeps the context small on every invocation.

---

## The facts survey

`gitf/gitf-survey.sh` is the single FACTS source. It runs once per invocation,
reads the live git DAG and `git worktree list`, and emits **one line of JSON** the
skill consumes verbatim. The skill never re-derives a fact (never re-parses a
remote URL, never re-counts commits) — if it isn't in the survey output, the
survey is extended.

The JSON has four blocks:

- `platform` — `provider` (github/local), `needs_login`, `has_remote`,
  `default_remote`. Capability is decided by *what `gh` can do*, not by the remote
  URL, so GitHub Enterprise works with no special handling.
- `branch` — `current`, `head`, `dirty`.
- `topology` — `is_develop`, `is_main`, `gitf_branch` (release/hotfix/null),
  `ahead_of_develop`, `merged_into_develop`, `ahead_of_origin`,
  `develop_ahead_of_main`. **Routing keys off topology, not branch-name prefixes**
  — a branch called `spike-foo` ahead of develop routes exactly like
  `feature/foo`.
- `worktrees` — `current_path`, `main_path`, `current_is_linked`, `develop_at`,
  `main_at`. Lets flows behave correctly when develop/main/release is checked out
  in a linked worktree.

The survey is the only script with non-trivial logic, and it is the only thing
with unit tests (`gitf/tests/test-survey.sh`, run pure-locally with no network).

---

## The operation contract

Flows and providers meet at five coarse verbs:

| Verb | Meaning |
|------|---------|
| `LAND base head [keep-branch]` | get the commits on `head` into `base` |
| `PUBLISH branch` | make a branch visible on the remote (if any) |
| `SYNC branch` | bring a local branch up to date with its remote (if any) |
| `TAG version` | annotated `v<version>` tag, published if a remote exists |
| `CLEANUP branch` | delete a branch locally and remotely (and remove its worktree) |

`LAND` is the only verb that differs *structurally* by platform: on github it is
an asynchronous, blockable PR cycle; on local it is a synchronous `git merge
--no-ff`. Everything else is a thin wrapper. This is why github is the only
provider that can "pause" — and why pausing needs no state (see below).

---

## Stateless resume, concretely

When a github `LAND` cannot complete (branch protection requires a review, CI is
running or failed), the flow stops with a message and writes nothing. The next
`/gitf` on that branch re-locates the PR by head→base — not by a stored number:

```bash
gh pr list --head <branch> --base <base> --state all --json number,state,mergeStateStatus
```

- `MERGED` → the land already happened, advance to the next step.
- `OPEN` + `CLEAN` → merge now.
- `OPEN` + `BLOCKED`/`UNSTABLE`/`UNKNOWN` → stop again with the reason.
- none / `CLOSED`-unmerged → start fresh (create the PR).

The git graph supplies the rest of "where was I": which release/hotfix branches
still carry commits not in `main`, whether a tag exists, whether the back-merge
landed. Flows are written to **probe before every action**, so re-running is
always safe — completed steps are detected and skipped.

The code-review gate (B-4 / C-2) runs *before* any PR exists, on the local branch
against `main..<branch>`. Its "resume" is simply re-running the gate from the top;
reviewers are detected live each run, never stored.

---

## Self-update & the two version files

The installed skill keeps itself current. On the first `/gitf` each week,
`gitf/gitf-update.sh` fetches `gitf/.version` from `main`, compares it to the
installed copy, and — if newer or if the multi-file layout is missing (an old
single-file install) — syncs the whole `gitf/` tree from a release tarball.

This is why **two** version numbers exist in this repo, and why they must be kept
in sync by hand:

| File | Role | Bumped by |
|------|------|-----------|
| `VERSION` (repo root) | the **project** version | `/gitf -v` (flow-b B-1 auto-detects it) |
| `gitf/.version` | the **shipped skill** version the self-updater compares | edited manually, in the same commit |

`/gitf -v` deliberately does **not** touch `gitf/.version`: B-1's version-file
detection (`package.json` → `pyproject.toml` → `Cargo.toml` → `VERSION`) is
generic shipped logic, and teaching it about `gitf/.version` would leak a
self-only special case onto every user. The duplication exists *only* because
this project's product is the skill itself (it dogfoods its own release). The
contract is recorded in the repo `CLAUDE.md`: **change `VERSION`, `gitf/.version`,
and the git tag together.**

---

## Where to change what

| You want to change… | Edit |
|---------------------|------|
| A fact the skill needs | `gitf/gitf-survey.sh` (+ a case in `tests/test-survey.sh`) |
| A Git Flow step (order, what a release does) | the relevant `gitf/flows/flow-*.md` |
| How a verb runs on GitHub or locally | `gitf/providers/github.md` or `local.md` |
| Routing / the decision tree | `gitf/SKILL.md` **and** `spec/decision-tree.md` |
| A user-facing message | `gitf/flows/status-messages.md` |
| The code-review gate behavior | `gitf/flows/code-review-gate.md` |

There are **no build steps**. The skill is plain Markdown + shell.

---

## Testing

- **Survey unit tests**: `bash gitf/tests/test-survey.sh` — capability, topology,
  and worktree cases against mock git states. Pure-local, no network, exit 0 =
  green. `tests/` is dev-only and is excluded from what ships to users.
- **Behavioral evals**: `evals/evals.json` drives `/skill-creator`, which runs
  subagents against the skill end-to-end. Workspace output goes in
  `gitf-workspace/` (gitignored).

The spec under [`spec/`](../spec/) is the authoritative behavioral contract the
evals are written against; `gitf/SKILL.md` is its executable form. When they
disagree, `SKILL.md` wins and the spec is corrected.
