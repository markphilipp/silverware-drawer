#!/bin/bash
set -euo pipefail

LABEL="com.bar-peekaboo"
BIN_DIR="$HOME/.local/bin"
BIN_NAME="bar-peekaboo"
BIN_PATH="$BIN_DIR/$BIN_NAME"
PLIST_NAME="$LABEL.plist"
PLIST_PATH="$HOME/Library/LaunchAgents/$PLIST_NAME"
LOG_PATH="/tmp/bar-peekaboo.log"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$SCRIPT_DIR/bar-peekaboo.swift"

echo "==> Compiling bar-peekaboo..."
mkdir -p "$BIN_DIR"
swiftc -O "$SRC" -o "$BIN_PATH"

echo "==> Installing launch agent..."
# Unload existing agent if present
launchctl unload "$PLIST_PATH" 2>/dev/null || true

cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$BIN_PATH</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$LOG_PATH</string>
    <key>StandardErrorPath</key>
    <string>$LOG_PATH</string>
</dict>
</plist>
EOF

launchctl load "$PLIST_PATH"

echo "==> bar-peekaboo installed and running"
echo "    Logs: tail -f $LOG_PATH"
