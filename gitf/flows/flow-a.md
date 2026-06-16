# Flow A — Feature/Fix → Develop

**Trigger**: on `feature/*` or `fix/*`.

Steps (verbs resolved by the active provider):

1. `LAND base=develop head=<current-branch>`
2. On success → `SYNC develop` → **status-messages: flow-a-done**

**PR/commit title** (github provider): derive from the branch name in
Conventional Commits form.
- `feature/auth-jwt` → `feat(auth): implement JWT authentication`
- `fix/map-markers` → `fix(map): correct marker positioning`

**github provider**: if `LAND` reports the PR blocked, it has already saved
`.git/gitf-state.json` (`flow=A, step=awaiting_merge`) and emitted a `blocked-*`
message. Stop there; the next `/gitf` resumes via `resume.md`.

**local provider**: `LAND` is a synchronous `--no-ff` merge into develop, then
push develop if `has_remote`. Never blocks, never writes state. Delete the
feature/fix branch (`CLEANUP <current-branch>`) and report `flow-a-done`.
