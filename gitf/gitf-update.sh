#!/usr/bin/env bash
# gitf-update.sh
# Keeps the installed gitf skill up to date. Called automatically by the skill.
#
# The skill is now multi-file (SKILL.md + flows/ + providers/ + scripts), so this
# syncs the whole gitf/ directory from a release tarball rather than fetching a
# single file. Also doubles as the self-heal path for old single-file installs.

set -euo pipefail

REPO="syoslyot/gitf-skill"
INSTALL_DIR="$HOME/.claude/skills/gitf"
CHECK_INTERVAL=604800  # 7 days
LAST_CHECK_FILE="/tmp/gitf-last-check"
VERSION_URL="https://raw.githubusercontent.com/$REPO/main/gitf/.version"
TARBALL_URL="https://codeload.github.com/$REPO/tar.gz/refs/heads/main"

INSTALLED=$(cat "$INSTALL_DIR/.version" 2>/dev/null | tr -d '[:space:]' || echo "unknown")

# Heal trigger: multi-file layout missing means an old single-file install.
NEEDS_HEAL="false"
if [ ! -d "$INSTALL_DIR/flows" ] || [ ! -d "$INSTALL_DIR/providers" ]; then
  NEEDS_HEAL="true"
fi

# --- Throttle: skip if checked recently AND nothing to heal ---
NOW=$(date +%s)
LAST=$(cat "$LAST_CHECK_FILE" 2>/dev/null || echo 0)
if [ "$NEEDS_HEAL" = "false" ] && [ $(( NOW - LAST )) -lt $CHECK_INTERVAL ]; then
  exit 0
fi

# --- Latest version (tiny request) ---
LATEST=$(curl -sf --max-time 3 "$VERSION_URL" | tr -d '[:space:]' || true)
echo "$NOW" > "$LAST_CHECK_FILE"

if [ -z "$LATEST" ]; then
  # Network unavailable — don't block the user.
  exit 0
fi

# Up to date and healthy: nothing to do.
if [ "$NEEDS_HEAL" = "false" ] && [ "$LATEST" = "$INSTALLED" ]; then
  exit 0
fi

# --- Download tarball and sync the gitf/ subtree ---
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

if ! curl -sf --max-time 20 "$TARBALL_URL" -o "$TMP/gitf.tar.gz"; then
  exit 0
fi
if ! tar -xzf "$TMP/gitf.tar.gz" -C "$TMP" 2>/dev/null; then
  exit 0
fi

# Extracted root is "<repo>-main"; the skill lives in its gitf/ subdir.
SRC=$(find "$TMP" -maxdepth 2 -type d -name gitf | head -n1)
if [ -z "$SRC" ] || [ ! -f "$SRC/SKILL.md" ]; then
  exit 0
fi

mkdir -p "$INSTALL_DIR"
# Mirror the source tree into the install dir. Use rsync if available for a
# clean delete-extraneous sync; otherwise fall back to cp. tests/ is dev-only —
# exclude it so it never lands in a user's install.
if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete --exclude 'tests/' "$SRC/" "$INSTALL_DIR/"
else
  cp -R "$SRC/." "$INSTALL_DIR/"
fi
# Prune dev-only files (covers the cp fallback and cleans older installs that
# shipped tests/ before this exclusion existed).
rm -rf "$INSTALL_DIR/tests"

chmod +x "$INSTALL_DIR/gitf-survey.sh" "$INSTALL_DIR/gitf-update.sh" 2>/dev/null || true

if [ "$NEEDS_HEAL" = "true" ] && [ "$INSTALLED" = "$LATEST" ]; then
  echo "gitf healed: restored multi-file layout (v$LATEST)"
else
  echo "gitf updated: $INSTALLED → $LATEST"
fi
