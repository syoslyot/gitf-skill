# Flow C — Hotfix

**Trigger**: on `hotfix/*`.

Same two-land pattern as Flow B (main first, then back-merge to develop), but
the version is **always a patch bump** — patching production always gets a tag.

### C-1: Patch version

Detect the version file (same order as Flow B), always compute a **patch** bump.

### C-2: Code-review gate

Run the shared code-review gate (`flows/code-review-gate.md`) on
`<hotfix-branch>` against `main..<hotfix-branch>`. If it stops with unresolved
findings, state is saved (`flow=C, step=awaiting_code_review`,
`release_branch=<hotfix-branch>`) and the run halts here; otherwise continue to
C-3.

### C-3: Land hotfix → main

`PUBLISH <hotfix-branch>` then `LAND base=main head=<hotfix-branch> keep-branch`.

- github: blocked → save state (`flow=C, step=awaiting_merge`, `target_branch=main`) → stop.
- local: synchronous merge into main, push if `has_remote`.

### C-4: Tag main

`TAG <patch-version>` — after main has the hotfix, before the back-merge.

### C-5: Land hotfix → develop

`LAND base=develop head=<hotfix-branch>` (github: `--head <hotfix-branch>`).

- github: blocked → update state (`step=awaiting_merge`, `target_branch=develop`) → stop.
- local: synchronous merge into develop, push if `has_remote`.

### C-6: Cleanup

`CLEANUP <hotfix-branch>` → `SYNC develop` → delete state (github) →
**status-messages: flow-c-done**.
