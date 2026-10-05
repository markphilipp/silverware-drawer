# BarPeekaboo

Toggles the macOS menu bar based on which display is primary:

- **Built-in (laptop) display is main** → menu bar hidden (auto-hide on)
- **External display is main** → menu bar visible

Reacts to display changes (plug/unplug monitors, switching primary) via
`hs.screen.watcher` (after a 1s settle delay), toggling the System Events "autohide menu bar" preference.

## Options

| Option | Default | Effect |
| --- | --- | --- |
| `builtinPattern` | `"Built%-in"` | Lua pattern matched against the display name to find the built-in display. |

Hammerspoon doesn't expose `CGDisplayIsBuiltin`, so the built-in display is
detected by name. If yours reports something else (e.g. `Color LCD`,
`Liquid Retina`), override it per machine:

```lua
{ name = "BarPeekaboo", opts = { builtinPattern = "Liquid Retina" } }
```
