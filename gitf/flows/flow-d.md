# Flow D — Rescue (AI forgot to branch)

**Trigger**: on the integration branch (`topology.integration` — `develop` in a
gitflow repo, `main` in a trunk repo) with uncommitted changes (Case 1) or with
commits ahead of its upstream (Case 2).

`<integration>` below means that branch. The rescue is identical either way: the
AI committed onto the branch it was supposed to branch *from*.

This flow is **identical across providers** — branch creation, renaming, and
`reset --hard` are all local git. After rescuing, it hands off to **Flow A**.

### Case 1 — uncommitted changes on `<integration>`

```bash
git checkout -b <inferred-name>   # uncommitted changes follow automatically
```

Then → Flow A.

### Case 2 — rogue commits on `<integration>` — **gitflow only**

**Does not apply when `topology.model == "trunk"`.** On a single trunk,
committing directly to it is how the model works; those commits are not rogue
and must never be hard-reset. A trunk repo with unpushed commits on its trunk
needs `PUBLISH <integration>` (a plain push), not a rescue — see the decision
tree, rule 1a.

```bash
git checkout -b <inferred-name>
git checkout <integration>
git reset --hard origin/<integration>   # local-only repo: reset to the pre-rogue ref instead
git checkout <inferred-name>
```

Then → Flow A.

**Branch naming**: infer from commit messages + changed file paths. Format
`feature/<scope>-<kebab-desc>` or `fix/<scope>-<kebab-desc>`. Always report the
chosen name and the reasoning to the user.

**Postcondition**: `<integration>` is back in sync with its upstream (or its
pre-rogue state in a local-only repo).
