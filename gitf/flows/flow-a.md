# Flow A — Topic branch → Integration branch

**Trigger**: on any topic branch (any name; not the integration branch/main/
release/hotfix) with `topology.ahead_of_integration>0`, or
`topology.merged_into_integration` with the branch/worktree still present
(cleanup-only re-run).

Throughout, `<integration>` means `topology.integration` — `develop` in a gitflow
repo, `main` in a trunk repo. Never substitute a hardcoded branch name.

Steps (verbs resolved by the active provider):

1. **[trunk + version only]** code-review gate — see below
2. `LAND base=<integration> head=<current-branch>`
3. On success → `SYNC <integration>` → `CLEANUP <current-branch>` (github deletes
   the PR branch on merge; still call CLEANUP to remove any worktree and local ref)
4. **[trunk + version only]** bump + tag — see below
5. **status-messages: flow-a-done** (trunk → `flow-a-done-trunk`)

**Cleanup-only re-run**: if routed here with `topology.merged_into_integration=true`
and the branch/worktree still present (the prior run merged but could not finish
cleanup, e.g. a leaked worktree), skip `LAND` and run `CLEANUP <current-branch>`
directly, then **status-messages: flow-a-done**.

**PR/commit title** (github provider): derive from the branch name in
Conventional Commits form.
- `feature/auth-jwt` → `feat(auth): implement JWT authentication`
- `fix/map-markers` → `fix(map): correct marker positioning`

**github provider**: if `LAND` reports the PR blocked, emit the matching
`blocked-*` message and stop. No state is written — the next `/gitf` re-locates
the PR via `gh pr list --head <current-branch>` (see providers/github.md) and
continues.

**local provider**: `LAND` is a synchronous `--no-ff` merge into `<integration>`,
then push it if `has_remote`. Never blocks, never writes state. Delete the topic
branch (`CLEANUP <current-branch>`) and report `flow-a-done`.

---

## Trunk repos: release happens here

A trunk repo has no Flow B and no Flow C — there is no develop→main promotion to
make, and no separate production line to hotfix. Landing on `main` **is** the
release. So the two things Flow B owns in a gitflow repo, the review gate and the
version tag, belong to Flow A when `topology.model == "trunk"`; without this a
single-trunk repo could never cut a version at all.

Both run **only** when `VERSION_MODE=true`. A plain `/gitf` on a trunk repo is
ordinary day-to-day integration — gating and tagging every such merge would be
noise, and it is the tag, not the merge, that marks a release.

### Code-review gate (step 1)

`model == "trunk"` and `VERSION_MODE=true` and not `SKIP_REVIEW`: load
`flows/code-review-gate.md` and run it on the topic branch before `LAND`. Same
semantics as B-4 — production code is about to ship.

### Bump + tag (step 4)

On `<integration>` (= `main`), after `SYNC`:

1. **Find the current version** from whichever source the repo has, in order:
   `VERSION`, `package.json` (`.version`), `pyproject.toml` (`project.version`),
   `Cargo.toml` (`package.version`), then the newest `v*` tag. If none exists,
   start from `v0.1.0` and say so.
2. **Decide the bump** from the landed commits — `feat:` → minor, `fix:`/`chore:`
   → patch, a breaking change → major. State the inferred level and the resulting
   version. Ask only when the commits genuinely do not settle it.
3. **Write it back** if a version file exists: commit on `main` as
   `chore: bump version to v<X.Y.Z>`, then push.
4. `TAG <version>` — annotated tag `v<X.Y.Z>`, published when a remote exists.

There is no back-merge step: in a trunk repo there is nothing to back-merge into.
