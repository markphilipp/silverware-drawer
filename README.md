# be-right-back

A small collection of [Hammerspoon](https://www.hammerspoon.org/) **spoons** for
macOS automation, with a per-machine installer. The repo is shared across
machines via git; an `fzf` picker chooses which spoons run on *this* machine, so
each computer keeps its own set without touching the shared code.

## Spoons

| Spoon | What it does |
| --- | --- |
| **BeRightBack** | Caffeinate the display while unlocked, release it on lock (and a general lock/unlock action framework). |
| **BarPeekaboo** | Show the menu bar when the built-in display is primary, hide it when an external display is. |

## Requirements

- [Hammerspoon](https://www.hammerspoon.org/)
- [`fzf`](https://github.com/junegunn/fzf) (`brew install fzf`)

## Install

```sh
./install.sh
```

You get an `fzf` multi-picker of the available spoons — `TAB` to toggle, `Enter`
to confirm (`●` marks spoons already enabled on this machine). The installer
then:

- symlinks the selected spoons into `~/.hammerspoon/Spoons/`
- writes your selection to `~/.hammerspoon/be-right-back.config.lua` (per machine)
- symlinks the loader to `~/.hammerspoon/be-right-back.lua`
- adds `require("be-right-back")` to `~/.hammerspoon/init.lua` if missing

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
require("be-right-back")
```

That resolves to the loader (`load.lua`, symlinked in), which reads the
per-machine `be-right-back.config.lua` and `hs.loadSpoon` + `:start()`s each
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

Every spoon exposes a uniform `:start()` / `:stop()` contract.

## BeRightBack

Keeps the display awake (caffeinated) while unlocked and releases it on lock so
the screen sleeps normally — no Caffeine app required, it uses `hs.caffeinate`.

Set `assertion = "systemIdle"` (via config `opts`) to keep the *whole system*
awake instead of just the display.

It's also a general lock-event framework. Register extra actions, each a table
with optional `onLock` / `onUnlock` functions:

```lua
spoon.BeRightBack:register({
  onLock   = function() hs.spotify.pause() end,
  onUnlock = function() hs.spotify.play() end,
})
```

Action errors are caught and logged to the Hammerspoon console so one failing
action won't break the rest.

## BarPeekaboo

Toggles the macOS menu bar based on which display is primary:

- **Built-in (laptop) display is main** → menu bar visible
- **External display is main** → menu bar hidden

Reacts to display changes (plug/unplug monitors, switching primary) via
`hs.screen.watcher`, toggling the System Events "autohide menu bar" preference.

Hammerspoon doesn't expose `CGDisplayIsBuiltin`, so the built-in display is
detected by matching its name against `builtinPattern` (default `"Built%-in"`).
If your built-in display reports a different name (e.g. `Color LCD`,
`Liquid Retina`), override it per machine via config `opts`.

## License

MIT
