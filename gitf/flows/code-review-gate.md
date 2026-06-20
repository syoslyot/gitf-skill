# Code-Review Gate (shared by Flow B step B-4 and Flow C step C-2)

Runs on the release/hotfix branch **before** it lands on `main`, against the
local diff `main..<branch>`. Platform-independent — the PR (if any) does not
exist yet.

## Inputs

- `<branch>` — the current `release/*` or `hotfix/*` branch.
- `SKIP_REVIEW` — from `/gitf --skip-review`.
- Reviewers — detected live this run, in preference order, keeping those that
  exist: (1) `code-review` skill/plugin, (2) `superpowers:requesting-code-review`,
  (3) `review` skill. `ls ~/.claude/skills/ 2>/dev/null` plus the session's
  visible skill list. Use the single highest-preference one by default.

## Procedure

```
IF SKIP_REVIEW=true → skip the gate, continue to the next flow step.

Detect reviewers (above). IF none are available → skip the gate, continue.

FOR each reviewer in order:
  Invoke that review tool on the diff main..<branch>.
  Read its output and JUDGE whether there are findings that must be fixed.
  (Do NOT hardcode any "empty == pass" rule — different tools emit different
   shapes. Decide from the content whether real, blocking issues exist.)

  IF no blocking findings → continue to the next reviewer.

  IF blocking findings the AI can fix itself:
    Fix them, commit to <branch>, then re-run THIS SAME reviewer.

  IF blocking findings needing the user (can't fix / design decision):
    Emit status-messages: blocked-code-review listing the remaining findings, and
    STOP. No state is written. On the next `/gitf`, routing lands back on this
    release/* (or hotfix/*) branch and re-enters this gate from the top
    (idempotent): resolved findings pass, unresolved ones stop again.

When every reviewer passes → continue to the next flow step.
```

## Resume

There is no saved state. Re-running `/gitf` on a release/* or hotfix/* branch that
has not yet landed on `main` re-enters this gate from the top and re-runs every
reviewer. Only once the gate passes does the flow proceed to landing on `main`.
