#!/usr/bin/env bash
# Smart, per-machine installer for the silverware-drawer spoon collection.
#
# Presents an fzf multi-picker of the available spoons, symlinks the selected
# ones into Hammerspoon, and writes a per-machine config the loader reads. The
# repo is shared across machines; the selection lives outside the repo so each
# machine keeps its own set.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPOONS_SRC="$REPO/spoons"
HS_DIR="$HOME/.hammerspoon"
SPOON_DST_DIR="$HS_DIR/Spoons"
CONFIG="$HS_DIR/silverware-drawer.config.lua"
LOADER_DST="$HS_DIR/silverware-drawer.lua"
INIT="$HS_DIR/init.lua"
REQUIRE_LINE='require("silverware-drawer")'

if ! command -v fzf >/dev/null 2>&1; then
  echo "error: fzf is required but not found on PATH." >&2
  echo "       install it (e.g. 'brew install fzf') and re-run." >&2
  exit 1
fi

check_accessibility() {
  if ! command -v hs >/dev/null 2>&1; then
    echo "warning: Hammerspoon CLI 'hs' not found; Accessibility could not be checked." >&2
    return
  fi

  local state
  state="$(hs -c 'print(hs.accessibilityState())' 2>/dev/null || true)"
  case "$state" in
    *true*) ;;
    *false*)
      echo "error: Hammerspoon does not have Accessibility permission." >&2
      echo "       Enable it in System Settings > Privacy & Security > Accessibility." >&2
      echo "       Then rerun ./install.sh." >&2
      exit 1
      ;;
    *)
      echo "warning: Hammerspoon is not running; Accessibility could not be checked." >&2
      ;;
  esac
}

check_accessibility

# --- discover spoons -------------------------------------------------------
# Read a one-line description from each spoon's '--- === Name ===' header: the
# first prose '--- ...' line that isn't the title banner.
spoon_desc() {
  grep -m1 -E '^--- [^=]' "$1/init.lua" 2>/dev/null | sed -E 's/^--- //' || true
}

declare -a NAMES=()
for dir in "$SPOONS_SRC"/*.spoon; do
  [ -d "$dir" ] || continue
  NAMES+=("$(basename "$dir" .spoon)")
done

if [ "${#NAMES[@]}" -eq 0 ]; then
  echo "error: no spoons found in $SPOONS_SRC" >&2
  exit 1
fi

# --- clean dead spoons ------------------------------------------------------
# Remove repo-owned spoon links that can no longer work: the link target is
# gone (e.g. a deleted worktree) or the spoon no longer exists in spoons/.
# Stale config entries drop out when the config is rewritten below; warn there
# so the disappearance is visible. Never touch links that don't point into
# this repo.
is_available() { local n; for n in "${NAMES[@]}"; do [ "$n" = "$1" ] && return 0; done; return 1; }

for link in "$SPOON_DST_DIR"/*.spoon; do
  [ -L "$link" ] || continue
  target="$(readlink "$link")"
  [[ "$target" == "$REPO/"* ]] || continue
  name="$(basename "$link" .spoon)"
  if [ ! -e "$link" ] || ! is_available "$name"; then
    rm -f "$link"
    echo "✗ removed dead spoon link: $name -> $target"
  fi
done

# --- currently-enabled set (for display markers) ---------------------------
currently_enabled() {
  [ -f "$CONFIG" ] || return 0
  # Pull bare names and name= entries out of the Lua config.
  grep -oE '"[A-Za-z0-9_]+"|name *= *"[A-Za-z0-9_]+"' "$CONFIG" \
    | grep -oE '"[A-Za-z0-9_]+"' | tr -d '"' | sort -u
}
ENABLED_BEFORE="$(currently_enabled || true)"

is_enabled() { grep -qxF "$1" <<<"$ENABLED_BEFORE"; }

# Config entries with no matching spoon in the repo silently vanish when the
# config is rewritten — call them out so the user knows why.
while IFS= read -r name; do
  [ -n "$name" ] || continue
  is_available "$name" || echo "! dropping '$name' from config — no such spoon in $SPOONS_SRC"
done <<<"$ENABLED_BEFORE"

# --- order: currently-enabled spoons first ---------------------------------
# fzf has no flag to pre-mark rows, but a bind can select them for us. So sort
# the enabled spoons to the top and select exactly that many; the rest follow.
# Result: the picker opens with the current set highlighted.
declare -a ENABLED_NAMES=() OTHER_NAMES=()
for name in "${NAMES[@]}"; do
  if is_enabled "$name"; then ENABLED_NAMES+=("$name"); else OTHER_NAMES+=("$name"); fi
done
NAMES=( ${ENABLED_NAMES[@]+"${ENABLED_NAMES[@]}"} ${OTHER_NAMES[@]+"${OTHER_NAMES[@]}"} )
SELECT_COUNT="${#ENABLED_NAMES[@]}"

# Pre-select the leading SELECT_COUNT rows. Use the `load` event (not `start`):
# `start` fires before the piped list is read, so there is nothing to select
# yet. `pos(i)` addresses rows absolutely, so cursor/layout direction is moot.
PRESELECT="load:"
for ((i = 1; i <= SELECT_COUNT; i++)); do PRESELECT+="pos($i)+select+"; done
PRESELECT+="pos(1)"

# --- build picker lines ----------------------------------------------------
# Format: "Name\tName — desc" — Name is field 1 (hidden), the rest is shown.
# Selection state is shown by fzf itself (full-line highlight + marker); the
# currently-enabled spoons come up pre-selected (see PRESELECT above).
picker_input() {
  local name desc
  for name in "${NAMES[@]}"; do
    desc="$(spoon_desc "$SPOONS_SRC/$name")"
    if [ -n "$desc" ]; then
      printf '%s\t%s — %s\n' "$name" "$name" "$desc"
    else
      printf '%s\t%s\n' "$name" "$name"
    fi
  done
}

echo "Select spoons to enable on this machine."
echo "  Highlighted rows = selected. SPACE or TAB toggles; ENTER confirms."
SELECTED="$(picker_input | fzf --multi --with-nth=2.. --delimiter='\t' \
  --no-sort --highlight-line --cycle \
  --pointer='▶' --marker='✓ ' \
  --color='pointer:green,marker:green,selected-bg:22,selected-fg:255,hl:cyan,hl+:cyan,bg+:238' \
  --bind 'space:toggle' \
  --bind "$PRESELECT" \
  --prompt='spoons> ' \
  --header=$'SPACE / TAB: toggle    ENTER: confirm    ESC: cancel' \
  | cut -f1 || true)"

if [ -z "$SELECTED" ]; then
  read -r -p "No spoons selected — disable all on this machine? [y/N] " ans
  [[ "$ans" =~ ^[Yy]$ ]] || { echo "Aborted; nothing changed."; exit 0; }
fi

# --- apply symlinks --------------------------------------------------------
mkdir -p "$SPOON_DST_DIR"

# Remove symlinks for previously-enabled spoons that point into this repo —
# including worktree paths (so deselecting actually unlinks). Never touch
# unrelated/real spoons.
while IFS= read -r name; do
  [ -n "$name" ] || continue
  link="$SPOON_DST_DIR/$name.spoon"
  if [ -L "$link" ] && [[ "$(readlink "$link")" == "$REPO/"* ]]; then
    rm -f "$link"
  fi
done <<<"$ENABLED_BEFORE"

# Symlink selected spoons.
while IFS= read -r name; do
  [ -n "$name" ] || continue
  src="$SPOONS_SRC/$name.spoon"
  dst="$SPOON_DST_DIR/$name.spoon"
  rm -rf "$dst"
  ln -s "$src" "$dst"
  echo "✓ linked $name"
done <<<"$SELECTED"

# --- write per-machine config ----------------------------------------------
{
  echo "-- Generated by silverware-drawer install.sh — per machine, do not commit."
  echo "-- Re-run ./install.sh to change the enabled set."
  echo "return {"
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    echo "  \"$name\","
  done <<<"$SELECTED"
  echo "}"
} >"$CONFIG"
echo "✓ wrote $CONFIG"

# --- loader symlink + init.lua line ----------------------------------------
rm -f "$LOADER_DST"
ln -s "$REPO/load.lua" "$LOADER_DST"
echo "✓ linked loader -> $LOADER_DST"

if [ -f "$INIT" ]; then
  if grep -qF "$REQUIRE_LINE" "$INIT"; then
    : # already present
  else
    printf '\n%s\n' "$REQUIRE_LINE" >>"$INIT"
    echo "✓ added '$REQUIRE_LINE' to $INIT"
  fi
else
  echo
  echo "No $INIT found. Create it with this line:"
  echo "    $REQUIRE_LINE"
fi

# --- reload ----------------------------------------------------------------
echo
if command -v hs >/dev/null 2>&1; then
  hs -c "hs.reload()" >/dev/null 2>&1 && echo "✓ reloaded Hammerspoon" || \
    echo "Reload Hammerspoon to apply (Hammerspoon menu → Reload Config)."
else
  echo "Reload Hammerspoon to apply (Hammerspoon menu → Reload Config)."
fi
