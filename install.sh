#!/usr/bin/env bash
# Symlink the BeRightBack Spoon into Hammerspoon and print the load snippet.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPOON_SRC="$REPO/BeRightBack.spoon"
SPOON_DIR="$HOME/.hammerspoon/Spoons"
SPOON_DST="$SPOON_DIR/BeRightBack.spoon"

mkdir -p "$SPOON_DIR"

if [ -L "$SPOON_DST" ] || [ -e "$SPOON_DST" ]; then
  rm -rf "$SPOON_DST"
fi

ln -s "$SPOON_SRC" "$SPOON_DST"
echo "✓ Linked $SPOON_DST -> $SPOON_SRC"
echo
echo "Add these lines to ~/.hammerspoon/init.lua, then reload Hammerspoon:"
echo
echo '    hs.loadSpoon("BeRightBack")'
echo '    spoon.BeRightBack:start()'
