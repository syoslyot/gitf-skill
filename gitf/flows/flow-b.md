# Flow B — Full Release to Main

**Trigger**: on `develop` with commits ahead of `main`, or resuming on an
existing `release/*` branch.

Steps marked **[version only]** run only when `-v` was passed (`VERSION_MODE=true`).
Everything here except `LAND` is platform-independent — version detection,
bumping, and tagging are plain git.

**Resuming on an existing `release/*` branch via cache-miss** (state was lost, so
the `-v` flag from the original run is gone): infer `version_mode` and `version`
from the branch name instead of the flag — `release/v<X.Y.Z>` → `version_mode=true`,
`version=<X.Y.Z>`; `release/<YYYY-MM-DD>` → `version_mode=false`. This keeps tag
handling (B-6) correct without the saved entry. (When triggered fresh from
`develop`, use the `-v` flag as normal.)

### B-0: In-flight guard (cache-miss, when triggered from develop)

A release must wait for any in-flight production change: you do not ship a release
while a hotfix is unfinished, nor start a second release while one is open. Before
creating a release branch, probe for an existing unmerged release **or** hotfix
branch:

```bash
git branch --list 'release/*' 'hotfix/*' | sed 's/^[* ] *//' | while read -r b; do
  [ -n "$(git log main.."$b" --oneline)" ] && echo "BLOCKER:$b"
done
```

If any `BLOCKER:` printed → **halt**: tell the user an unfinished release or
hotfix branch exists and to merge or delete it before starting a release. Do not
create a new release branch and do not append `-2`.

### B-1: Determine release name

**[version only]**: read the version file (order below), determine the bump from
commit history, compute the new version. Release branch = `release/v<new-version>`.

**[no version]**: release branch = `release/<YYYY-MM-DD>`. If that name already
exists, append `-2`, `-3`, …

Version file detection order:
1. `package.json` (if `.ts/.js/.tsx/.jsx` files exist)
2. `pyproject.toml` (if `.py` is primary)
3. `Cargo.toml` (if `.rs` is primary)
4. `VERSION` (fallback — create with `0.1.0` if none found)

Bump type from `git log main..develop --oneline`:
- only `fix:` → patch
- any `feat:` → minor
- `BREAKING CHANGE` in body → major (confirm with user first)

### B-2: Create or resume the release branch

Idempotency (cache-miss resume): if `<release-branch>` already exists — e.g. you
were routed here already standing on it (`On release/* → flow-b.md`) — do **not**
recreate it and do **not** `git checkout develop`. Just make sure you are on it:

```bash
git checkout <release-branch>
```

Otherwise (fresh release triggered from develop):

```bash
git checkout develop && git pull   # SYNC develop first if has_remote
git checkout -b <release-branch>
```

### B-3 [version only]: Bump version file

Idempotency (cache-miss): if the version file already equals `<new-version>`, or a
`chore: bump version` commit already exists on this branch, skip B-3.

Edit only the version field:
- `package.json` → `"version": "<new-version>"`
- `pyproject.toml` / `Cargo.toml` → `version = "<new-version>"`
- `VERSION` → overwrite

```bash
git add <version-file>
git commit -m "chore: bump version to v<new-version>"
```

### B-4: Code-review gate

Run the shared code-review gate (`flows/code-review-gate.md`) on
`<release-branch>` against `main..<release-branch>`. If it stops with unresolved
findings, state is saved (`step=awaiting_code_review`) and the run halts here;
otherwise continue to B-5.

### B-5: Land release → main

`PUBLISH <release-branch>` then `LAND base=main head=<release-branch> keep-branch`.

`keep-branch` is required — the release branch is still needed for the
back-merge in B-7.

- github: if blocked, save the entry keyed by `<release-branch>` and stop:
  ```bash
  pause_sha=$(git rev-parse "<release-branch>")
  bash ~/.claude/skills/gitf/gitf-state.sh put "<release-branch>" \
    '{"flow":"B","step":"awaiting_merge_to_main","pr_number":<n>,"source_branch":"<release-branch>","target_branch":"main","release_branch":"<release-branch>","version":<version-or-null>,"version_mode":<true|false>,"main_pr_merged":false,"develop_pr_number":null,"pause_sha":"'"$pause_sha"'"}'
  ```
- local: synchronous merge into main, push main if `has_remote`.

### B-6 [version only]: Tag main

`TAG <new-version>` — only after main has the release commit, never before B-5,
never after B-7.

### B-7: Land release → develop (back-merge)

`LAND base=develop head=<release-branch>` (no `keep-branch` — done with it after).

- github: must create the back-merge PR with `--head <release-branch>` (current
  branch may be `main`). If blocked, update the entry (still keyed by
  `<release-branch>`) and stop:
  ```bash
  pause_sha=$(git rev-parse "<release-branch>")
  bash ~/.claude/skills/gitf/gitf-state.sh put "<release-branch>" \
    '{"flow":"B","step":"awaiting_merge_to_develop","pr_number":<develop-pr-n>,"source_branch":"<release-branch>","target_branch":"develop","release_branch":"<release-branch>","version":<version-or-null>,"version_mode":<true|false>,"main_pr_merged":true,"develop_pr_number":<develop-pr-n>,"pause_sha":"'"$pause_sha"'"}'
  ```
- local: synchronous merge into develop, push if `has_remote`.

### B-8: Cleanup

`CLEANUP <release-branch>` → `SYNC develop` → drop the entry
(`gitf-state.sh del "<release-branch>"`; `CLEANUP` already does this, harmless to
repeat) → **status-messages: flow-b-done**.

**Tag ordering invariant**: always between B-5 (main has the commit) and B-7.
