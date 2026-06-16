# /gitf — One-Time Setup

Read and run this **only** when `SKILL.md`'s bootstrap reports
`GITF_NOT_CONFIGURED` (no `.gitf/config` in the current repo). It runs once per
project; afterwards `/gitf` skips it entirely.

It writes the per-project config that `/gitf` reads on every run. Nothing here
touches global state — everything lives under the project's `.gitf/`.

---

## Step 1: Detect available review tools

The code-review gate (B-4 / C-2) drives whatever review skill the user already
has. Look for these, in this preference order, and keep the ones that exist:

1. `code-review` — `~/.claude/skills/code-review/` or a `code-review` plugin skill
2. `superpowers:requesting-code-review` — superpowers plugin
3. `review` — `~/.claude/skills/review/`

```bash
ls ~/.claude/skills/ 2>/dev/null
```

Also consider plugin-provided skills visible in the session's skill list.

## Step 2: Ask the user which reviewer(s) to use

- Present the detected tools. **Default: the single highest-preference tool.**
- Only configure multiple (run in order) if the user explicitly asks for it.
- If none are installed, set `reviewers: []` — the gate is then a no-op and
  `/gitf` releases without review.

## Step 3: Write `.gitf/config`

```bash
mkdir -p .gitf
```

Write `.gitf/config` as JSON:

```json
{
  "platform": "auto",
  "reviewers": ["code-review"]
}
```

- `platform`: leave `"auto"` unless the user wants to force `"github"` / `"local"`.
- `reviewers`: the ordered list chosen in Step 2 (or `[]`).

## Step 4: Ignore the `.gitf/` directory

`.gitf/` holds tool state and is not part of the repo. Append `.gitf/` to the
project's `.gitignore` if not already present.

After these steps, return to `SKILL.md` and continue the normal flow.

---

## Background: platforms

`/gitf` runs on one of two providers, chosen automatically every run by
`gitf-detect.sh` (never cached):

- **github** — `gh` is installed and logged in, and the repo has a remote. Uses
  PRs; can pause on review/CI and resume later.
- **local** — no remote, or `gh` missing/not-logged-in, or `platform:"local"` in
  `.gitf/config`. Synchronous `--no-ff` merges, no PRs.

GitLab/Bitbucket native MR/PR are intentionally not implemented; non-GitHub
remotes fall back to `local`. To force local on a GitHub repo, set
`platform:"local"` in `.gitf/config`.
