# Flow D — Rescue (AI forgot to branch)

**Trigger**: on `develop` with uncommitted changes (Case 1) or with commits
ahead of `origin/develop` (Case 2).

This flow is **identical across providers** — branch creation, renaming, and
`reset --hard` are all local git. After rescuing, it hands off to **Flow A**.

### Case 1 — uncommitted changes on develop

```bash
git checkout -b <inferred-name>   # uncommitted changes follow automatically
```

Then → Flow A.

### Case 2 — rogue commits on develop

```bash
git checkout -b <inferred-name>
git checkout develop
git reset --hard origin/develop   # local-only repo: reset to the pre-rogue ref instead
git checkout <inferred-name>
```

Then → Flow A.

**Branch naming**: infer from commit messages + changed file paths. Format
`feature/<scope>-<kebab-desc>` or `fix/<scope>-<kebab-desc>`. Always report the
chosen name and the reasoning to the user.

**Postcondition**: `develop` is back in sync with its upstream (or its
pre-rogue state in a local-only repo).
