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
5. Report:
   - gitflow → **status-messages: flow-a-done**
   - trunk, `VERSION_MODE=false` → **status-messages: flow-a-done-trunk**
   - trunk, `VERSION_MODE=true` → **status-messages: flow-a-done-trunk (version)**

   Pick by `VERSION_MODE`, not by whether a tag happened to be created — a run
   that skipped tagging because the tag already existed still released.

**Cleanup-only re-run**: if routed here with `topology.merged_into_integration=true`
and the branch/worktree still present (the prior run merged but could not finish
cleanup, e.g. a leaked worktree), skip steps 1-2 and run `CLEANUP <current-branch>`
directly.

**On this path, when `model == "trunk"` and `VERSION_MODE=true`, run `SYNC
<integration>` and then step 4.** The land already happened but the bump and tag
may not have, and skipping them would silently lose the version. `SYNC` is not
optional here: it both fetches the merge commit (under the github provider it
exists only on the remote) and checks out `<integration>`, without which the bump
would commit onto a stale local branch and the tag would land on the topic-branch
tip instead of the merge commit. Then report as in step 5.

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
branch (`CLEANUP <current-branch>`) and report per step 5 — which message
depends on `model` and `VERSION_MODE`, not on the provider.

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

### Bump + tag (step 4) {#release-step}

Runs on `<integration>`, after `SYNC <integration>` has checked it out. Also
reachable directly from the decision tree when standing on `<integration>` in a
trunk repo with `-v` (see SKILL.md rule 1b′).

1. **Find the version source**, in order: `VERSION`, `package.json`
   (`.version`), `pyproject.toml` (`project.version`), `Cargo.toml`
   (`package.version`). Call its current value `<cur>`. If no file exists, use
   the newest `v*` tag; if there is none either, start at `0.1.0` and say so.

2. **Decide whether to bump — this is the idempotency point.**

   ```
   IF `git tag -l v<cur>` is EMPTY  → <cur> was never released.
                                      Do NOT bump. Tag <cur>. Go to step 4.
   ELSE                             → <cur> is already released. Bump it.
   ```

   Keying off "does the file already hold the *newly computed* version" is wrong
   and loses a version: a run interrupted between the bump commit and the tag
   leaves the file at `1.4.0` untagged, and a re-run would compute `1.5.0` from
   the commits, bump again, and tag `v1.5.0` — `v1.4.0` never exists. Keying off
   whether `<cur>` is tagged makes the re-run tag `v1.4.0` and stop, which is
   what the interrupted run was about to do.

3. **Bump** (only when step 2 said to): `feat:` → minor, `fix:`/`chore:` →
   patch, a breaking change → major, computed from the landed commits. State the
   inferred level and the result. Write the file, commit on `<integration>` as
   `chore: bump version to v<X.Y.Z>`, then push.

4. `TAG <version>` — annotated tag `v<X.Y.Z>`, published when a remote exists.
   Skip if `git tag -l v<version>` is already non-empty.

There is no back-merge step: in a trunk repo there is nothing to back-merge into.
