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

- github: blocked → save the entry keyed by `<hotfix-branch>` and stop:
  ```bash
  pause_sha=$(git rev-parse "<hotfix-branch>")
  bash ~/.claude/skills/gitf/gitf-state.sh put "<hotfix-branch>" \
    '{"flow":"C","step":"awaiting_merge","pr_number":<n>,"source_branch":"<hotfix-branch>","target_branch":"main","release_branch":"<hotfix-branch>","version":"<patch-version>","version_mode":true,"main_pr_merged":false,"develop_pr_number":null,"pause_sha":"'"$pause_sha"'"}'
  ```
- local: synchronous merge into main, push if `has_remote`.

### C-4: Tag main

`TAG <patch-version>` — after main has the hotfix, before the back-merge.

### C-5: Land hotfix → develop

`LAND base=develop head=<hotfix-branch>` (github: `--head <hotfix-branch>`).

- github: blocked → update the entry (still keyed by `<hotfix-branch>`) and stop:
  ```bash
  pause_sha=$(git rev-parse "<hotfix-branch>")
  bash ~/.claude/skills/gitf/gitf-state.sh put "<hotfix-branch>" \
    '{"flow":"C","step":"awaiting_merge","pr_number":<develop-pr-n>,"source_branch":"<hotfix-branch>","target_branch":"develop","release_branch":"<hotfix-branch>","version":"<patch-version>","version_mode":true,"main_pr_merged":true,"develop_pr_number":<develop-pr-n>,"pause_sha":"'"$pause_sha"'"}'
  ```
- local: synchronous merge into develop, push if `has_remote`.

### C-6: Cleanup

`CLEANUP <hotfix-branch>` → `SYNC develop` → drop the entry
(`gitf-state.sh del "<hotfix-branch>"`; `CLEANUP` already does this) →
**status-messages: flow-c-done**.
