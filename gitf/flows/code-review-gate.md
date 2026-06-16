# Code-Review Gate (shared by Flow B step B-4 and Flow C step C-2)

Runs on the release/hotfix branch **before** it lands on `main`, against the
local diff `main..<branch>`. Platform-independent — the PR (if any) does not
exist yet.

## Inputs

- `<branch>` — the current `release/*` or `hotfix/*` branch.
- `SKIP_REVIEW` — from `/gitf --skip-review`.
- `.gitf/config` → `reviewers`: ordered list of review tools to run.

## Procedure

```
IF SKIP_REVIEW=true → skip the gate, continue to the next flow step.

Read reviewers from .gitf/config.
IF reviewers is empty / missing → skip the gate, continue.

FOR each reviewer in order:
  Invoke that review tool on the diff main..<branch>.
  Read its output and JUDGE whether there are findings that must be fixed.
  (Do NOT hardcode any "empty == pass" rule — different tools emit different
   shapes. Decide from the content whether real, blocking issues exist.)

  IF no blocking findings → continue to the next reviewer.

  IF blocking findings the AI can fix itself:
    Fix them, commit to <branch>, then re-run THIS SAME reviewer.

  IF blocking findings needing the user (can't fix / design decision):
    Capture the pause point and write the entry keyed by <branch>:
    ```bash
    pause_sha=$(git rev-parse "<branch>")
    bash ~/.claude/skills/gitf/gitf-state.sh put "<branch>" \
      '{"flow":"<B|C>","step":"awaiting_code_review","pr_number":null,"release_branch":"<branch>","version":<version-or-null>,"version_mode":<true|false>,"main_pr_merged":false,"develop_pr_number":null,"pause_sha":"'"$pause_sha"'"}'
    ```
    <branch> is the release/* branch (Flow B) or the hotfix/* branch (Flow C);
    resume reads release_branch from there. Schema is in SKILL.md.
    Emit status-messages: blocked-code-review listing the remaining findings.
    STOP.

When every reviewer passes → continue to the next flow step.
```

## Resume

On `step=awaiting_code_review` the next `/gitf` re-enters this gate from the top
(re-running every reviewer). Only once the gate passes does the flow proceed to
landing on `main`.
