#!/usr/bin/env bash
# gitf-update.sh
# Checks if the installed gitf skill is outdated and auto-updates if needed.
# Called automatically by the skill — no need to run this manually.

set -euo pipefail

REPO="syoslyot/git-flow-skill"
INSTALL_DIR="$HOME/.claude/skills/gitf"
CHECK_INTERVAL=604800  # seconds between checks (7 days)
LAST_CHECK_FILE="/tmp/gitf-last-check"
VERSION_URL="https://raw.githubusercontent.com/$REPO/main/gitf/.version"
SKILL_URL="https://raw.githubusercontent.com/$REPO/main/gitf/SKILL.md"

# --- Check interval: skip if checked recently ---
NOW=$(date +%s)
LAST=$(cat "$LAST_CHECK_FILE" 2>/dev/null || echo 0)
if [ $(( NOW - LAST )) -lt $CHECK_INTERVAL ]; then
  exit 0
fi

# --- Fetch latest version (single tiny request) ---
LATEST=$(curl -sf --max-time 3 "$VERSION_URL" || true)
if [ -z "$LATEST" ]; then
  # Network unavailable — silently skip, don't block the user
  echo "$NOW" > "$LAST_CHECK_FILE"
  exit 0
fi

LATEST=$(echo "$LATEST" | tr -d '[:space:]')
INSTALLED=$(cat "$INSTALL_DIR/.version" 2>/dev/null | tr -d '[:space:]' || echo "unknown")

# --- Record check time regardless of result ---
echo "$NOW" > "$LAST_CHECK_FILE"

if [ "$LATEST" = "$INSTALLED" ]; then
  exit 0
fi

# --- Update SKILL.md and .version ---
UPDATED_SKILL=$(curl -sf --max-time 5 "$SKILL_URL" || true)
if [ -z "$UPDATED_SKILL" ]; then
  exit 0
fi

echo "$UPDATED_SKILL" > "$INSTALL_DIR/SKILL.md"
echo "$LATEST" > "$INSTALL_DIR/.version"

echo "gitf updated: $INSTALLED → $LATEST"
