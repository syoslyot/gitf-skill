# Flow Resume

Reached on a **cache hit** (Step 0.5): the current branch has a valid entry.

```bash
current=$(git branch --show-current)
entry=$(bash ~/.claude/skills/gitf/gitf-state.sh get "$current")
```

Read `flow` and `step` from `entry`, then branch on `step`:

- `step=awaiting_code_review` → **code-review pause** (either provider). Re-enter
  the code-review gate (`flows/code-review-gate.md`) from the top on `current`
  (the release/* branch for Flow B, or the hotfix/* branch for Flow C — also held
  in `release_branch`). If it passes, continue the owning flow: Flow B from B-5,
  Flow C from C-3. If it stops again, the entry stays and the run halts. No PR is
  involved here.
- any other `step` → **PR-merge pause** (github only); follow the rest of this
  file.

## PR-merge pause (github)

Check the waiting PR:

```bash
gh pr view <pr_number> --json state,mergeStateStatus,statusCheckRollup
```

| `state` | `mergeStateStatus` | Action |
|---------|--------------------|--------|
| `MERGED` | — | continue to the next step (table below) |
| `OPEN` | `BLOCKED` | **status-messages: blocked-review** |
| `OPEN` | `UNSTABLE` | **status-messages: blocked-ci-failed** |
| `OPEN` | `UNKNOWN` / pending | **status-messages: blocked-ci-running** |
| `CLOSED` (not merged) | — | **status-messages: pr-closed** → `gitf-state.sh del "$current"` |

## Next step after the waiting PR merged

| Flow | Step | Action |
|------|------|--------|
| A | `awaiting_merge` | `SYNC develop` → `del "$current"` → **flow-a-done** |
| B | `awaiting_merge_to_main` | `TAG` if `version_mode` → `LAND release→develop` → merge or save entry → **flow-b-done** or stop |
| B | `awaiting_merge_to_develop` | `CLEANUP <release-branch>` → `SYNC develop` → `del "$current"` → **flow-b-done** |
| C | `awaiting_merge` (target=main) | `TAG <patch-version>` → `LAND hotfix→develop` → merge or save entry |
| C | `awaiting_merge` (target=develop) | `CLEANUP <hotfix-branch>` → `SYNC develop` → `del "$current"` → **flow-c-done** |

Drop a branch's entry only when its flow is complete, or when its PR was found
`CLOSED` without merge (reset for a fresh start):

```bash
bash ~/.claude/skills/gitf/gitf-state.sh del "$current"
```

Note: `CLEANUP` already drops the entry for the branch it deletes (see the
provider). The explicit `del "$current"` above covers the cases where the
resumed branch is not the one being cleaned up.
