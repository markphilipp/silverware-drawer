#!/bin/bash
set -euo pipefail

LABEL="com.bar-peekaboo"
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"

if launchctl list | grep -q "$LABEL"; then
    launchctl unload "$PLIST_PATH"
    echo "bar-peekaboo stopped"
else
    echo "bar-peekaboo is not running"
fi
