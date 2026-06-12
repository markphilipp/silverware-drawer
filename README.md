# silverware-drawer

A small collection of [Hammerspoon](https://www.hammerspoon.org/) **spoons** for
macOS automation, with a per-machine installer. The repo is shared across
machines via git; an `fzf` picker chooses which spoons run on *this* machine, so
each computer keeps its own set without touching the shared code.

## Spoons

| Spoon | What it does |
| --- | --- |
| **BeRightBack** | Caffeinate the display while unlocked, release it on lock (and a general lock/unlock action framework). |
| **BarPeekaboo** | Show the menu bar when the built-in display is primary, hide it when an external display is. |
| **WindowCarousel** | Cycle through the focused app's windows with a hotkey. |
| **PullSpoon** | Fast-forward every repo's default branch under `~/Projects` daily at 4am, stashing/restoring local changes safely. |

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

## PullSpoon

Keeps every repo's default branch current without you thinking about it. Once a
day (default **4am**) it scans `~/Projects` recursively, finds each git repo, and
fast-forwards its default branch (`main`/`master`/…, read from `origin/HEAD`) to
match origin. If the Mac was asleep at the scheduled time, it catches up on the
next wake.

Discovery walks the tree for each repo's `.git`/`.bare` marker, pruning
`node_modules`, `vendor`, and hidden dirs, and stops at each repo root — so a
repo vendored inside another repo's working tree is left alone. Multiple
worktrees of the same repo are refreshed once, at whichever checkout holds the
default branch.

Handles every layout uniformly — normal clones, bare-repo + worktree projects
(`repo/.bare` with `repo/main`), and shared worktrees — and refreshes the
default branch wherever it lives:

- **not checked out** → the ref is fast-forwarded directly, no working tree touched
- **checked out, clean** → `git pull --ff-only`
- **checked out with uncommitted changes** → stash → pull → restore. If the pull
  isn't a fast-forward, or restoring the stash conflicts, the repo is rolled back
  to *exactly* its prior state (branch, working tree, index, untracked, stash all
  intact) and skipped — handle it by hand, or let the next run try again.

Repos with no `origin` remote are skipped silently.

Trigger a refresh by hand from the Hammerspoon console with
`spoon.PullSpoon:run()`. The work runs off the main thread via `hs.task`; a
summary is posted via `hs.notify` only when a run has skips or failures.

Per-machine `opts`:

```lua
{ name = "PullSpoon", opts = {
    root = os.getenv("HOME") .. "/Projects",  -- scanned root
    at = "04:00",                             -- daily run time, "HH:MM"
    sshAuthSock = "/path/to/agent.sock",      -- SSH agent for fetches outside a login shell
    notifyOnIssues = true,                    -- notify only on skips/failures
} }
```

`sshAuthSock` defaults to the 1Password agent socket so SSH fetches authenticate
even though the scheduled run has no login shell; set it to your machine's agent
socket, or `false` to rely on the inherited environment.

The underlying logic lives in `refresh-default-branches.sh` and can be run
directly (`PROJECTS_ROOT=~/Projects ./refresh-default-branches.sh`).

## License

MIT
