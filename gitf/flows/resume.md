# Flow Resume

Reached when `.gitf/state.json` exists. Read the state file first and branch on
`step`:

- `step=awaiting_code_review` → **code-review pause** (either provider). Re-enter
  the code-review gate (`flows/code-review-gate.md`) on `release_branch` from the
  top. If it passes, continue the owning flow: Flow B from B-5, Flow C from C-3.
  If it stops again, state stays and the run halts. No PR is involved here.
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
| `CLOSED` (not merged) | — | **status-messages: pr-closed** → delete state file |

## Next step after the waiting PR merged

| Flow | Step | Action |
|------|------|--------|
| A | `awaiting_merge` | `SYNC develop` → delete state → **flow-a-done** |
| B | `awaiting_merge_to_main` | `TAG` if `version_mode` → `LAND release→develop` → merge or save state → **flow-b-done** or stop |
| B | `awaiting_merge_to_develop` | `CLEANUP <release-branch>` → `SYNC develop` → delete state → **flow-b-done** |
| C | `awaiting_merge` (target=main) | `TAG <patch-version>` → `LAND hotfix→develop` → merge or save state |
| C | `awaiting_merge` (target=develop) | `CLEANUP <hotfix-branch>` → `SYNC develop` → delete state → **flow-c-done** |

Delete `.gitf/state.json` only when the entire flow is complete, or when a
PR was found `CLOSED` without merge (reset for a fresh start).
