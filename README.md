# silverware-drawer

A small collection of [Hammerspoon](https://www.hammerspoon.org/) **spoons** for
macOS automation, with a per-machine installer. The repo is shared across
machines via git; an `fzf` picker chooses which spoons run on *this* machine, so
each computer keeps its own set without touching the shared code.

## Spoons

| Spoon | What it does |
| --- | --- |
| [**BeRightBack**](spoons/BeRightBack.spoon/README.md) | Caffeinate the display while unlocked, release it on lock (and a general lock/unlock action framework). |
| [**BarPeekaboo**](spoons/BarPeekaboo.spoon/README.md) | Hide the menu bar when the built-in display is primary, show it when an external display is. |
| [**WindowCarousel**](spoons/WindowCarousel.spoon/README.md) | Cycle through the focused app's windows with a hotkey. |
| [**PullMyMainFinger**](spoons/PullMyMainFinger.spoon/README.md) | Fast-forward every repo's default branch under `~/Projects` while you're idle (at most once every 8h), stashing/restoring local changes safely. |
| [**WorkFocus**](spoons/WorkFocus.spoon/README.md) | Enable macOS Work Focus while active; clear it after five minutes idle. |
| [**BazecorNames**](spoons/BazecorNames.spoon/README.md) | Sync Bazecor layer, macro, and superkey names between machines through an iCloud file. |

## Requirements

- [Hammerspoon](https://www.hammerspoon.org/)
- [`fzf`](https://github.com/junegunn/fzf) (`brew install fzf`)

Hammerspoon must have Accessibility permission. Enable **System Settings →
Privacy & Security → Accessibility → Hammerspoon** before running the installer.
The installer checks this when the `hs` command is available and stops if
permission is explicitly disabled. If Hammerspoon is not running, it prints a
warning and the check can be completed after launching Hammerspoon.

## Install

```sh
./install.sh
```

You get an `fzf` multi-picker of the available spoons — `TAB` to toggle, `Enter`
to confirm (`●` marks spoons already enabled on this machine). The installer
then:

- symlinks the selected spoons into `~/.hammerspoon/Spoons/`
- writes your selection to `~/.hammerspoon/silverware-drawer.config.lua` (per machine)
- symlinks the loader to `~/.hammerspoon/silverware-drawer.lua`
- adds `require("silverware-drawer")` to `~/.hammerspoon/init.lua` if missing

Re-run `./install.sh` anytime to change the enabled set.

## Uninstall

```sh
./uninstall.sh          # unlink spoons + loader, drop the require line
./uninstall.sh --purge  # also delete the per-machine config
```

## How it works

`~/.hammerspoon/init.lua` needs exactly one stable line, regardless of which
spoons are enabled:

```lua
require("silverware-drawer")
```

That resolves to the loader (`load.lua`, symlinked in), which reads the
per-machine `silverware-drawer.config.lua` and `hs.loadSpoon` + `:start()`s each
enabled spoon. The config is intentionally **not** committed — it lives next to
your Hammerspoon config so the shared repo stays machine-agnostic.

Config entries are a spoon name, or a table with per-spoon options applied
before `:start()`:

```lua
return {
  "BeRightBack",
  { name = "BarPeekaboo", opts = { builtinPattern = "Built%-in" } },
}
```

Per-spoon options are documented in each spoon's README.

## Contributing

See [AGENTS.md](AGENTS.md) for repo conventions (also useful for humans).

## License

MIT
