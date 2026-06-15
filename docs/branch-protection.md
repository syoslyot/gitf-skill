# Branch Protection

## Recommended settings

Protect `main` and `develop` to prevent accidental direct pushes, while keeping `/gitf` functional.

### What to enable

- **Require a pull request before merging** ✅
  - Required approvals: **0** (you're working alone; PRs are for structure, not review gates)
  - Dismiss stale pull request approvals: off
- **Do not allow bypassing the above settings**: leave **unchecked**

### What to leave off

- Require status checks: off (unless you add CI)
- Require signed commits: off
- Restrict who can push: off

## Why this works with /gitf

`/gitf` never pushes directly to `main` or `develop` — it always creates a PR and merges through the API (`gh pr merge`). With 0 required approvals and bypass allowed, the skill can merge its own PRs without being blocked.

If you enable **required reviews** or **required status checks**, `gh pr merge` will fail and the skill will stop mid-flow.

## Setup (GitHub web UI)

1. Go to `github.com/<you>/git-flow-skill` → **Settings** → **Branches**
2. Click **Add branch ruleset** (or **Add rule** on older UI)
3. Branch name pattern: `main`
4. Enable: **Require a pull request before merging**, set approvals to 0
5. Repeat for `develop`

## Setup (gh CLI)

```bash
# Protect main
gh api repos/{owner}/{repo}/branches/main/protection \
  --method PUT \
  --field required_pull_request_reviews=null \
  --field enforce_admins=false \
  --field restrictions=null \
  --field required_status_checks=null

# Protect develop  
gh api repos/{owner}/{repo}/branches/develop/protection \
  --method PUT \
  --field required_pull_request_reviews=null \
  --field enforce_admins=false \
  --field restrictions=null \
  --field required_status_checks=null
```

> Note: GitHub's branch protection API requires at least one rule to be set. The above enables protection with no blocking requirements — it prevents direct pushes while allowing the repo owner to merge PRs freely.
