# Flow C — Hotfix

**Trigger**: on `hotfix/*`.

Same two-land pattern as Flow B (main first, then back-merge to develop), but
the version is **always a patch bump** — patching production always gets a tag.

### C-0: In-flight guard

A hotfix is the highest-priority change, so it does **not** wait for an in-flight
release (that release will wait for this hotfix — see B-0). It only conflicts with
**another** unfinished hotfix. Probe for an other unmerged hotfix branch (exclude
the one you are on — it is unmerged by definition; do not probe `release/*`):

```bash
current=$(git branch --show-current)
git branch --list 'hotfix/*' | sed 's/^[* ] *//' | while read -r b; do
  [ "$b" = "$current" ] && continue
  [ -n "$(git log main.."$b" --oneline)" ] && echo "BLOCKER:$b"
done
```

If any `BLOCKER:` printed → **halt**: tell the user another unfinished hotfix
branch exists and to merge or delete it before running `/gitf` again. Do not
guess.

### C-1: Patch version

Detect the version file (same order as Flow B), always compute a **patch** bump.

### C-2: Code-review gate

Run the shared code-review gate (`flows/code-review-gate.md`) on
`<hotfix-branch>` against `main..<hotfix-branch>`. If it stops with unresolved
findings the run halts here (no state written); re-running `/gitf` on this
`hotfix/*` branch re-enters the gate idempotently. Otherwise continue to C-3.

### C-3: Land hotfix → main

`PUBLISH <hotfix-branch>` then `LAND base=main head=<hotfix-branch> keep-branch`.

- github: if blocked, emit `blocked-*` and stop. No state. Next `/gitf` on this
  `hotfix/*` branch re-locates the hotfix→main PR via
  `gh pr list --head <hotfix-branch> --base main --state all` and resumes.
- local: synchronous merge into main, push if `has_remote`.

### C-4: Tag main

`TAG <patch-version>` — after main has the hotfix, before the back-merge.

### C-5: Land hotfix → develop

`LAND base=develop head=<hotfix-branch>` (github: `--head <hotfix-branch>`).

- github: create the back-merge PR with `--head <hotfix-branch>`. If blocked,
  emit `blocked-*` and stop. No state. Next `/gitf` re-locates the
  hotfix→develop PR via `gh pr list --head <hotfix-branch> --base develop
  --state all` and resumes.
- local: synchronous merge into develop, push if `has_remote`.

### C-6: Cleanup

`CLEANUP <hotfix-branch>` → `SYNC develop` → **status-messages: flow-c-done**.
