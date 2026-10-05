# WindowCarousel

Cycle through the focused app's windows with a hotkey.

Moves focus to the next standard window of the frontmost app, in stable order
(sorted by window ID). Wraps at the end; no-op when the app has one window or
fewer.

## Options

| Option | Default | Effect |
| --- | --- | --- |
| `mods` | `{"ctrl","shift","alt","cmd"}` | Hotkey modifiers. |
| `key` | `"w"` | Hotkey key. |

```lua
{ name = "WindowCarousel", opts = { mods = {"ctrl", "alt"}, key = "tab" } }
```
