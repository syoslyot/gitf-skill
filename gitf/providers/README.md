# Providers

A **provider** implements the operation contract that flows depend on. Flows
(`flows/*.md`) never name a platform tool directly — they invoke coarse verbs,
and the active provider says how each verb is carried out on that platform.

`gitf-survey.sh` reports `platform.provider`, picking exactly one provider per
`/gitf` run. The skill loads that single provider file and no other.

## Operation contract

Every provider implements these coarse verbs. They are deliberately coarse:
GitHub and local are not "same verb, different command" — landing a branch on
GitHub is an async, blockable PR flow, while landing locally is a synchronous
merge. The `LAND` verb absorbs that structural difference so flows stay
platform-agnostic.

| Verb | Meaning |
|------|---------|
| `LAND base head [keep-branch]` | Get the commits on `head` into `base`. |
| `PUBLISH branch` | Make `branch` visible on the remote (if any). |
| `SYNC branch` | Bring local `branch` up to date with the remote (if any). |
| `TAG version` | Create annotated tag `v<version>` and publish it (if a remote exists). |
| `CLEANUP branch` | Delete `branch` locally and remotely (if it exists remotely). |

`LAND` is the only verb whose shape differs structurally between providers.
The others differ only by whether a remote exists.

## Survey fields

Providers read these fields from the survey JSON (`gitf-survey.sh`):

- `platform.has_remote` — whether `PUBLISH`/`SYNC`/remote cleanup do anything.
- `platform.default_remote` — remote name to push/pull against.
- `worktrees.develop_at` / `worktrees.main_path` — where `LAND` runs its merge and
  where `CLEANUP` steps out to before removing a branch's worktree.

## Pausing and resume (stateless)

No state file is written. Two things can pause a flow:

- **PR that cannot auto-merge** (await review / CI) — `github` only.
- **code-review gate** (B-4 / C-2) stopping with unresolved findings — **either**
  provider, since the review runs on the local branch before landing.

`local` only pauses on the code-review gate; every other local step lands
synchronously. On pause the flow emits a `blocked-*` message and stops — nothing
is persisted. The next `/gitf` re-derives position from the git graph and `gh`:
the github provider re-locates the PR with `gh pr list --head <branch> --base
<base> --state all`, and the code-review gate re-runs from the top. Idempotency
probes guard every action, and any ambiguity halts.

## Adding a platform

1. Add one capability case to `gitf-survey.sh` (only if a new capability must be
   probed; reusing `local` needs nothing).
2. Add `providers/<name>.md` implementing every verb above.
3. Leave flows and `SKILL.md` untouched.

GitLab/Bitbucket native MR/PR are intentionally **not** implemented — the
structure is reserved here, not built. Non-GitHub remotes fall back to `local`
(`/gitf --local`).
