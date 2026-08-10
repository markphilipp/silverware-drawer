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
| **PullMyMainFinger** | Fast-forward every repo's default branch under `~/Projects` while you're idle (at most once every 8h), stashing/restoring local changes safely. |
| **WorkFocus** | Enable macOS Work Focus while active; clear it after five minutes idle. |

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

## PullMyMainFinger

Keeps every repo's default branch current without you thinking about it. It
scans `~/Projects` recursively, finds each git repo, and fast-forwards its
default branch (`main`/`master`/…, read from `origin/HEAD`) to match origin.

Triggers once you've been away from the keyboard for `idleMinutes` (default
**5**) **with the screen still unlocked**, and only if it's been at least
`minHoursBetweenRuns` (default **8**) since the last successful run. Unlocked
matters: locking the screen locks 1Password too, and its SSH agent then refuses
to sign, so every fetch stalls on an authorization prompt nobody is there to
answer. Before touching any repo the run proves two things: the remote is
reachable at all (a just-woken or VPN-less machine resolves nothing, and git's
DNS timeout runs into *minutes* per repo), and the agent will actually sign
(`ssh-add -l` doesn't prove that — it lists identities a locked agent still
refuses to use). Either failing mid-run aborts the rest, since every remaining
repo would fail the same way. A DNS failure is reported as a network problem,
not an auth one, even though git prints "Could not read from remote repository"
for both.

Come back to the machine — or lock it — and a run in flight is cancelled.
Cancellation is cooperative: the script finishes the repo it's on and stops
before the next one, so nothing is ever killed between `stash push` and
`stash pop`.

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
`spoon.PullMyMainFinger:run()` (ignores the idle and `minHoursBetweenRuns`
gates), and stop one with `spoon.PullMyMainFinger:cancel()`. The work runs off
the main thread via `hs.task`; a summary is posted via `hs.notify` only when a
run has skips or failures worth a look, timestamped so an old one can't be
mistaken for a fresh failure (they don't auto-withdraw). A "not
fast-forwardable" skip (diverged local commits) and an unreachable network are
logged to the console but never notify — both are routine and self-resolving —
and a cancelled run doesn't notify at all.

Per-machine `opts`:

```lua
{ name = "PullMyMainFinger", opts = {
    root = os.getenv("HOME") .. "/Projects",  -- scanned root
    idleMinutes = 5,                          -- idle time before a run starts
    pollSeconds = 60,                         -- how often idle state is checked
    minHoursBetweenRuns = 8,                  -- min hours between successful runs
    sshAuthSock = "/path/to/agent.sock",      -- SSH agent for fetches outside a login shell
    notifyOnIssues = true,                    -- notify only on skips/failures
} }
```

`sshAuthSock` defaults to the 1Password agent socket so SSH fetches authenticate
even though the scheduled run has no login shell; set it to your machine's agent
socket, or `false` to rely on the inherited environment.

The underlying logic lives in `refresh-default-branches.sh` and can be run
directly (`PROJECTS_ROOT=~/Projects ./refresh-default-branches.sh`). It exits
`0` clean, `1` if a repo failed, `3` if the SSH agent can't sign, `4` if it was
cancelled with `SIGTERM`/`SIGINT`, and `5` if the remote is unreachable.
`NET_PROBE_HOST` (default `github.com`), `NET_PROBE_TIMEOUT`, and
`SSH_PROBE_TIMEOUT` tune the two preflight checks.

## License

MIT
