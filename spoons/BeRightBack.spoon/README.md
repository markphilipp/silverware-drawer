# BeRightBack

Keeps the display awake (caffeinated) while unlocked and releases it on lock so
the screen sleeps normally — no Caffeine app required, it uses `hs.caffeinate`.

## Options

Set via config `opts` (see the [root README](../../README.md#how-it-works)).

| Option | Default | Effect |
| --- | --- | --- |
| `assertion` | `"displayIdle"` | `hs.caffeinate` sleep type held while unlocked. `"systemIdle"` keeps the *whole system* awake instead of just the display. |

## Lock-event framework

Register extra actions, each a table with optional `onLock` / `onUnlock`
functions:

```lua
spoon.BeRightBack:register({
  onLock   = function() hs.spotify.pause() end,
  onUnlock = function() hs.spotify.play() end,
})
```

`:start()` applies the unlocked state immediately; `:stop()` releases the assertion. The caffeinate step always runs first, then registered actions in order.

Action errors are caught and logged to the Hammerspoon console so one failing
action won't break the rest.
