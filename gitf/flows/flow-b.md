# Flow B — Full Release to Main

**Trigger**: on `develop` with commits ahead of `main`, or resuming on an
existing `release/*` branch.

Steps marked **[version only]** run only when `-v` was passed (`VERSION_MODE=true`).
Everything here except `LAND` is platform-independent — version detection,
bumping, and tagging are plain git.

**Resuming on an existing `release/*` branch**: there is no saved `-v` flag, so
infer `version_mode`/`version` from the branch name — `release/v<X.Y.Z>` →
`version_mode=true, version=<X.Y.Z>`; `release/<YYYY-MM-DD>` → `version_mode=false`.
To resume **and** tag a date-named release, the user re-runs `/gitf -v`. Position
within the flow is derived from the graph + `gh` (see B-5/B-7 below), not state.

### B-0: In-flight guard (when triggered fresh from develop)

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

Idempotency: if `<release-branch>` already exists, just ensure you are on it
(`git checkout <release-branch>` in the current worktree); do not recreate it and
do not `git checkout develop`. Fresh release from develop: `SYNC develop` then
`git checkout -b <release-branch>` from develop's tip.

### B-3 [version only]: Bump version file

Idempotency (re-run): if the version file already equals `<new-version>`, or a
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
findings the run halts here (no state written); re-running `/gitf` on this
`release/*` branch re-enters the gate idempotently. Otherwise continue to B-5.

### B-5: Land release → main

`PUBLISH <release-branch>` then `LAND base=main head=<release-branch> keep-branch`.

`keep-branch` is required — the release branch is still needed for the
back-merge in B-7.

- github: if blocked, emit the matching `blocked-*` message and stop. No state.
  Next `/gitf` on this `release/*` branch re-locates the release→main PR via
  `gh pr list --head <release-branch> --base main --state all` — `MERGED` advances
  to B-6/B-7, `OPEN` is re-checked, `CLOSED`-unmerged restarts B-5.
- local: synchronous merge into main, push main if `has_remote`.

### B-6 [version only]: Tag main

`TAG <new-version>` — only after main has the release commit, never before B-5,
never after B-7.

### B-7: Land release → develop (back-merge)

`LAND base=develop head=<release-branch>` (no `keep-branch` — done with it after).

- github: create the back-merge PR with `--head <release-branch>` (current branch
  may be `main`). If blocked, emit `blocked-*` and stop. No state. Next `/gitf`
  re-locates the release→develop PR via
  `gh pr list --head <release-branch> --base develop --state all` and resumes:
  `MERGED` → B-8, `OPEN` → re-check, `CLOSED`-unmerged → recreate.
- local: synchronous merge into develop, push if `has_remote`.

### B-8: Cleanup

`CLEANUP <release-branch>` → `SYNC develop` → **status-messages: flow-b-done**.
(CLEANUP removes any worktree for the release branch; see the provider.)

**Tag ordering invariant**: always between B-5 (main has the commit) and B-7.
