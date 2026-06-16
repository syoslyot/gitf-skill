# Flow A — Feature/Fix → Develop

**Trigger**: on `feature/*` or `fix/*`.

Steps (verbs resolved by the active provider):

1. `LAND base=develop head=<current-branch>`
2. On success → `SYNC develop` → **status-messages: flow-a-done**

**PR/commit title** (github provider): derive from the branch name in
Conventional Commits form.
- `feature/auth-jwt` → `feat(auth): implement JWT authentication`
- `fix/map-markers` → `fix(map): correct marker positioning`

**github provider**: if `LAND` reports the PR blocked, save the entry keyed by
the current branch, then emit the `blocked-*` message and stop; the next `/gitf`
resumes via `resume.md`.

```bash
branch=$(git branch --show-current)
pause_sha=$(git rev-parse "$branch")
bash ~/.claude/skills/gitf/gitf-state.sh put "$branch" \
  '{"flow":"A","step":"awaiting_merge","pr_number":<n>,"source_branch":"'"$branch"'","target_branch":"develop","release_branch":null,"version":null,"version_mode":false,"main_pr_merged":false,"develop_pr_number":null,"pause_sha":"'"$pause_sha"'"}'
```

**local provider**: `LAND` is a synchronous `--no-ff` merge into develop, then
push develop if `has_remote`. Never blocks, never writes state. Delete the
feature/fix branch (`CLEANUP <current-branch>`) and report `flow-a-done`.
