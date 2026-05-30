#!/usr/bin/env bash
# Remove be-right-back from this machine: unlink its spoons and loader, and
# drop the require line from init.lua. The per-machine enabled config is left
# in place unless --purge is given. Never touches the repo itself.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPOONS_SRC="$REPO/spoons"
HS_DIR="$HOME/.hammerspoon"
SPOON_DST_DIR="$HS_DIR/Spoons"
CONFIG="$HS_DIR/be-right-back.config.lua"
LOADER_DST="$HS_DIR/be-right-back.lua"
INIT="$HS_DIR/init.lua"
REQUIRE_LINE='require("be-right-back")'

PURGE=0
[ "${1:-}" = "--purge" ] && PURGE=1

# Remove spoon symlinks that point into this repo.
if [ -d "$SPOON_DST_DIR" ]; then
  for link in "$SPOON_DST_DIR"/*.spoon; do
    [ -L "$link" ] || continue
    if [[ "$(readlink "$link")" == "$SPOONS_SRC/"* ]]; then
      rm -f "$link"
      echo "✓ unlinked $(basename "$link" .spoon)"
    fi
  done
fi

# Remove loader symlink.
if [ -L "$LOADER_DST" ]; then
  rm -f "$LOADER_DST"
  echo "✓ removed loader symlink"
fi

# Strip the require line from init.lua.
if [ -f "$INIT" ] && grep -qF "$REQUIRE_LINE" "$INIT"; then
  tmp="$(mktemp)"
  grep -vF "$REQUIRE_LINE" "$INIT" >"$tmp" && mv "$tmp" "$INIT"
  echo "✓ removed require line from init.lua"
fi

if [ "$PURGE" -eq 1 ] && [ -f "$CONFIG" ]; then
  rm -f "$CONFIG"
  echo "✓ purged $CONFIG"
elif [ -f "$CONFIG" ]; then
  echo "kept $CONFIG (use --purge to remove)"
fi

echo "Reload Hammerspoon to apply."
