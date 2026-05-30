#!/bin/bash
set -euo pipefail

LABEL="com.bar-peekaboo"
BIN_PATH="$HOME/.local/bin/bar-peekaboo"
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"

echo "==> Stopping bar-peekaboo..."
launchctl unload "$PLIST_PATH" 2>/dev/null || true

echo "==> Removing files..."
rm -f "$BIN_PATH" "$PLIST_PATH"

echo "==> bar-peekaboo uninstalled"
