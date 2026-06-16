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

Only a provider that can **block** (await review / CI) needs `.gitf/state.json`
and a resume path. Today that is `github` only. `local` lands synchronously and
**never** writes state.

## Adding a platform

1. Add one capability case to `gitf-detect.sh` (only if a new capability must be
   probed; reusing `local` needs nothing).
2. Add `providers/<name>.md` implementing every verb above.
3. Leave flows and `SKILL.md` untouched.

GitLab/Bitbucket native MR/PR are intentionally **not** implemented — the
structure is reserved here, not built. Non-GitHub remotes fall back to `local`
(set `.gitf/config` `{"platform":"local"}`).
