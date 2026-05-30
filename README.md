# be-right-back

`brb` — run automations when you lock and unlock your Mac.

When you step away, your machine should know. Lock the screen and `be-right-back`
fires off whatever you want it to. Unlock and it puts everything back the way you
left it.

The first behavior — and the reason it exists — is **caffeination**: keep the
display awake indefinitely while you're unlocked, and release it on lock so the
screen sleeps normally. No Caffeine app required; it uses macOS's own
`hs.caffeinate` via Hammerspoon.

## Install

Requires [Hammerspoon](https://www.hammerspoon.org/).

```sh
./install.sh
```

This symlinks `BeRightBack.spoon` into `~/.hammerspoon/Spoons/`. Then add to
`~/.hammerspoon/init.lua` and reload Hammerspoon:

```lua
hs.loadSpoon("BeRightBack")
spoon.BeRightBack:start()
```

That's it — you're caffeinated while unlocked, asleep-capable while locked.

## How it works

Hammerspoon's `hs.caffeinate.watcher` listens for `screensDidLock` /
`screensDidUnlock` events. On unlock it sets the `displayIdle` caffeinate
assertion (screen stays awake); on lock it clears it (screen sleeps per your
system settings).

To keep the **whole system** awake (not just the display), set the assertion
before starting:

```lua
spoon.BeRightBack.assertion = "systemIdle"
spoon.BeRightBack:start()
```

## Adding more actions

`be-right-back` is a general lock-event framework. Register extra actions —
each a table with optional `onLock` / `onUnlock` functions:

```lua
hs.loadSpoon("BeRightBack")

spoon.BeRightBack:register({
  onLock   = function() hs.spotify.pause() end,
  onUnlock = function() hs.spotify.play() end,
})

spoon.BeRightBack:start()
```

Action errors are caught and logged (Hammerspoon console) so one failing action
won't break the rest.

Ideas to grow into: pause media, mute mic & system audio, set Slack/Teams status
to away/DND, pause downloads & sync clients — and restore on unlock.

## License

MIT
