# Flow Specifications

Formal specification for each flow in `/gitf`. These define expected behavior for
evals and contributors.

> **Platform note.** The GitHub commands below describe the `github` provider.
> Flows themselves are written against platform-agnostic coarse verbs
> (`LAND`/`PUBLISH`/`SYNC`/`TAG`/`CLEANUP`) — see `gitf/flows/` and
> `gitf/providers/`. The `local` provider replaces each `gh` PR cycle with a
> synchronous `git merge --no-ff` and never blocks on a PR. The spec below is the
> GitHub-provider reference; for the verb contract see
> `gitf/providers/README.md`.

> **Numbering note.** Section labels below (B-1, B-2, …) match the step numbers in
> the executable flow files (`gitf/flows/flow-b.md`, `flow-c.md`), which are
> authoritative.

---

## Stateless resume model

`/gitf` writes **no** state file. A flow that cannot finish in one run (a blocked
PR, an unresolved review) simply stops with a message. The next `/gitf` on the
same branch re-derives where it was from two live sources:

1. **The git graph** — what is already merged into `main` / `develop`, which
   `release/*` or `hotfix/*` branches still carry commits not in `main`.
2. **GitHub PR status** — located by head→base, not by a stored PR number:

   ```bash
   gh pr list --head <branch> --base <base> --state all --json number,state,mergeStateStatus
   ```

Resolution by what that probe finds:

| PR `state` | `mergeStateStatus` | Action |
|------------|--------------------|--------|
| none / `CLOSED`-unmerged | — | treat as fresh — create (or recreate) the PR |
| `OPEN` | `CLEAN` | merge now |
| `OPEN` | `BLOCKED` | stop: waiting for review |
| `OPEN` | `UNSTABLE` | stop: CI failed |
| `OPEN` | `UNKNOWN` / pending | stop: CI still running |
| `MERGED` | — | this land already happened — advance to the next step |

Because position is reconstructed from the graph every time, multiple branches
can be paused at once, and resuming is always "run `/gitf` on the branch you have
checked out." Nothing can go stale, because nothing is stored.

The code-review gate (B-4 / C-2) has no PR yet — it runs on the local branch
before landing on `main`. Its "resume" is simply re-running the gate: a re-run of
`/gitf` on a `release/*` or `hotfix/*` branch that has not yet landed on `main`
re-enters the gate from the top and re-runs every reviewer (idempotent).

---

## Flow A — Topic branch → Develop

**Trigger**: a topic branch (any name not main/develop/release/hotfix) with
`ahead_of_develop > 0`; or, in CLEANUP-only mode, a topic branch already
`merged_into_develop` that still exists locally or as a worktree.

**Steps**:
1. `PUBLISH <branch>` — `git push -u origin <branch>` (github), no-op without a remote.
2. `LAND base=develop head=<branch>` — github opens a PR (Conventional Commits
   title) and merges when `mergeStateStatus=CLEAN`, deleting the branch; local
   does a `--no-ff` merge.
3. `SYNC develop` — bring local develop up to date.

**CLEANUP-only re-run**: if the survey reports the branch already merged into
develop but the branch (or its worktree) still lingers, Flow A skips landing and
only runs `CLEANUP <branch>` + `SYNC develop`. This is how an interrupted Flow A
finishes cleanly on the next run.

**Postconditions (success)**:
- Topic branch deleted locally and on the remote.
- Local develop in sync with origin/develop.

**Postconditions (blocked, github only)**:
- PR exists on GitHub; `/gitf` reported the blocking `mergeStateStatus`.
- No state file is written. The next `/gitf` re-locates the PR via `gh pr list`.

---

## Flow B — Full Release to Main

**Trigger**: on `develop` with `develop_ahead_of_main > 0`, or on an existing
`release/*` branch (continue an in-progress release).

### B-0: In-flight guard (when triggered fresh from develop)

Halt if any `release/*` or `hotfix/*` branch has commits not in `main`. Do not
open a second release or ship over an unfinished hotfix.

### B-1: Determine release name and version

**[version only, `-v`]**: detect the version file (`package.json` →
`pyproject.toml` → `Cargo.toml` → `VERSION`; create `VERSION` at `0.1.0` if none),
compute the bump from `git log main..develop` (only `fix:` → patch; any `feat:`
→ minor; `BREAKING CHANGE` → major, confirm first). Release branch =
`release/v<new-version>`.

**[no version]**: release branch = `release/<YYYY-MM-DD>` (append `-2`, `-3`, … on
collision).

### B-2: Create or resume the release branch

Idempotent: if `<release-branch>` already exists, just check it out in the current
worktree — do not recreate it. Fresh from develop: `SYNC develop`, then
`git checkout -b <release-branch>`.

### B-3 [version only]: Bump version file

Idempotent: skip if the version file already equals `<new-version>` or a
`chore: bump version` commit already exists on this branch. Otherwise edit only
the version field and `git commit -m "chore: bump version to v<new-version>"`.

### B-4: Code-review gate

Run the shared gate (`gitf/flows/code-review-gate.md`) on `main..<release-branch>`.
Reviewers are **detected live** (no stored config): the highest-preference
available tool of `code-review`, `superpowers:requesting-code-review`, `review`.
The AI judges each tool's output — fixes what it can (commit + re-run that
reviewer), and stops with the findings if something needs the user. Skipped when
no reviewer is available or `--skip-review` was passed.

### B-5: Land release → main

`PUBLISH <release-branch>` then `LAND base=main head=<release-branch> keep-branch`
(`keep-branch` because the branch is still needed for the back-merge). If github
blocks, stop with the blocking status — no state. The next `/gitf` re-locates the
release→main PR via `gh pr list --head <release-branch> --base main`.

### B-6 [version only]: Tag main

`TAG <new-version>` — only after `main` has the release commit, never before B-5,
never after B-7.

### B-7: Land release → develop (back-merge)

`LAND base=develop head=<release-branch>` (no `keep-branch`). On github the PR
must use `--head <release-branch>` (the current branch may be `main`). If blocked,
stop; the next `/gitf` re-locates the release→develop PR via `gh pr list`.

### B-8: Cleanup

`CLEANUP <release-branch>` (removes any worktree for it first, then deletes the
branch local + remote) → `SYNC develop` → report done.

**Tag ordering invariant**: the tag is always created between B-5 (main has the
commit) and B-7.

**Postconditions (success)**:
- `main` contains the release commit (+ version bump if `-v`), tagged
  `v<version>` when `-v`.
- `develop` contains the same via back-merge.
- Release branch deleted local + remote; its worktree (if any) removed.
- No state file exists (none is ever written).

---

## Flow C — Hotfix

**Trigger**: on `hotfix/*`.

Same two-land pattern as Flow B (first to `main`, tag, then back-merge to
`develop`), but:
- Branches from `main`, not develop.
- Version is always a **patch** bump (when `-v`).
- The code-review gate (C-2) runs on `main..hotfix/*` before landing on `main`.
- Resume is graph-derived exactly as in Flow B: `gh pr list --head <hotfix>`
  against each base re-locates the right PR.

---

## Flow D — Rescue (rogue work on develop)

**Trigger**: on `develop` with a dirty working tree or commits ahead of
origin/develop (the AI committed here by mistake).

### Case 1 — Uncommitted changes

```bash
git checkout -b <inferred-name>   # the working-tree changes follow automatically
```

### Case 2 — Rogue commits

```bash
git checkout -b <inferred-name>
git checkout develop && git reset --hard origin/develop
git checkout <inferred-name>
```

Both cases then continue into **Flow A**.

**Branch naming**: inferred from commit messages + changed file paths, formatted
`feature/<scope>-<desc>` or `fix/<scope>-<desc>`. Always report the chosen name
and the reasoning.

**Postcondition**: `develop` is back in sync with `origin/develop`; the rescued
work lands via Flow A.
