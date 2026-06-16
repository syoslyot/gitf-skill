# Providers

A **provider** implements the operation contract that flows depend on. Flows
(`flows/*.md`) never name a platform tool directly — they invoke coarse verbs,
and the active provider says how each verb is carried out on that platform.

`gitf-detect.sh` picks exactly one provider per `/gitf` run. The skill loads
that single provider file and no other.

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

## Capability fields

Providers read these fields from the detector JSON:

- `has_remote` — whether `PUBLISH`/`SYNC`/remote cleanup do anything.
- `default_remote` — remote name to push/pull against.

## State and resume

`.gitf/state.json` is a **v2 branch-keyed map** (`{"version":2,"flows":{...}}`),
accessed only via `gitf-state.sh` (get/put/del/list/valid). Each paused flow is
one entry keyed by its owning branch, so multiple branches can be suspended
independently. Two things can pause:

- **PR that cannot auto-merge** (await review / CI) — `github` only.
- **code-review gate** (B-4 / C-2) stopping with unresolved findings — **either**
  provider, since the review runs on the local branch before landing.

So `local` produces an entry only for `step=awaiting_code_review`; every other
local step lands synchronously with no state.

Resume is **by current branch**: Step 0.5 looks up the entry for the branch you
are on and validates its `pause_sha` (must be an ancestor of the current tip) to
reject a reused branch name. A valid entry is a **cache hit** → trust and resume.
A missing or stale entry is a **cache miss** → the flow re-derives progress from
git/gh idempotently (probe before each action) and halts on any ambiguity. The
flow writes/updates/deletes entries; `CLEANUP` also drops the entry it deletes.
A v1 (non-`flows`) file is treated as empty → everything is a cache miss, which
is the migration path.

## Adding a platform

1. Add one capability case to `gitf-detect.sh` (only if a new capability must be
   probed; reusing `local` needs nothing).
2. Add `providers/<name>.md` implementing every verb above.
3. Leave flows and `SKILL.md` untouched.

GitLab/Bitbucket native MR/PR are intentionally **not** implemented — the
structure is reserved here, not built. Non-GitHub remotes fall back to `local`
(set `.gitf/config` `{"platform":"local"}`).
