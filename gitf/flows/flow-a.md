# Flow A — Topic branch → Develop

**Trigger**: on any topic branch (any name; not develop/main/release/hotfix) with
`topology.ahead_of_develop>0`, or `topology.merged_into_develop` with the branch/
worktree still present (cleanup-only re-run).

Steps (verbs resolved by the active provider):

1. `LAND base=develop head=<current-branch>`
2. On success → `SYNC develop` → `CLEANUP <current-branch>` (github deletes the
   PR branch on merge; still call CLEANUP to remove any worktree and local ref) →
   **status-messages: flow-a-done**

**Cleanup-only re-run**: if routed here with `topology.merged_into_develop=true`
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

**local provider**: `LAND` is a synchronous `--no-ff` merge into develop, then
push develop if `has_remote`. Never blocks, never writes state. Delete the topic
branch (`CLEANUP <current-branch>`) and report `flow-a-done`.
