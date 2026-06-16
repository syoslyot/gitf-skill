# Contributing

## Editing the skill

The skill is split by concern:

- **`gitf/SKILL.md`** — slim core (routing, decision tree, rules, state schema). No flow details, no platform commands.
- **`gitf/flows/*.md`** — Git Flow steps as platform-agnostic coarse verbs (`LAND`, `PUBLISH`, `SYNC`, `TAG`, `CLEANUP`).
- **`gitf/providers/*.md`** — how each verb runs on a platform. Adding a platform = one new provider file (+ at most one detector case); flows and core stay untouched. See `gitf/providers/README.md`.
- **`gitf/gitf-detect.sh`** — capability detection. If you change its output, update `gitf/tests/test-detect.sh`.

## Testing changes

Detector unit tests (fast, offline):

```bash
bash gitf/tests/test-detect.sh
```

Skill behavior via Claude Code's `/skill-creator`:

1. Edit the relevant file under `gitf/`
2. Invoke `/skill-creator` in Claude Code
3. Point it at `evals/evals.json`
4. Compare outputs before/after

## Adding a new eval case

Edit `evals/evals.json` and add a new entry following the existing format. Include:
- A realistic branch state description
- The expected behavior (which flow, what actions)

## Git Flow for this repo

This repo uses the same Git Flow it documents:
- Branch from `develop` for any change
- PR back to `develop`
- Releases go through `release/*` to `main`

Never commit directly to `main` or `develop`.
