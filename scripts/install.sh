#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STATUSLINE_SRC="$SCRIPT_DIR/statusline.sh"
STATUSLINE_DST="$HOME/.claude/statusline.sh"
SETTINGS="$HOME/.claude/settings.json"

echo "agent-bar installer"
echo "==================="

# Check dependencies
for cmd in jq git; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: $cmd is required but not installed."
    exit 1
  fi
done

# Copy statusline script
cp "$STATUSLINE_SRC" "$STATUSLINE_DST"
chmod +x "$STATUSLINE_DST"
echo "Installed statusline.sh -> $STATUSLINE_DST"

# Update settings.json
if [ -f "$SETTINGS" ]; then
  # Check if statusLine already configured
  if jq -e '.statusLine' "$SETTINGS" &>/dev/null; then
    echo "statusLine already configured in $SETTINGS — skipping."
  else
    # Add statusLine config
    TMP=$(mktemp)
    jq '. + {"statusLine": {"type": "command", "command": "~/.claude/statusline.sh", "padding": 2}}' "$SETTINGS" > "$TMP"
    mv "$TMP" "$SETTINGS"
    echo "Added statusLine config to $SETTINGS"
  fi
else
  # Create minimal settings
  echo '{"statusLine":{"type":"command","command":"~/.claude/statusline.sh","padding":2}}' | jq '.' > "$SETTINGS"
  echo "Created $SETTINGS with statusLine config"
fi

echo ""
echo "Done! Restart Claude Code to see the status bar."
echo ""
echo "Optional: Edit the limits at the top of $STATUSLINE_DST"
echo "  CLAUDE_DAILY_LIMIT  — daily token budget (default: 10M)"
echo "  CLAUDE_WEEKLY_LIMIT — weekly token budget (default: 50M)"
echo "  CODEX_INPUT_RATE    — Codex input cost/token"
echo "  CODEX_OUTPUT_RATE   — Codex output cost/token"
