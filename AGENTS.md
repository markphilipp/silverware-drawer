# AGENTS.md

Hammerspoon spoons for macOS automation, installed per machine. See
[README.md](README.md) for user-facing install/usage; each spoon's docs live in
`spoons/<Name>.spoon/README.md`.

## Layout

- `spoons/<Name>.spoon/init.lua` — one spoon per dir; `README.md` beside it documents behavior and options.
- `load.lua` — loader, symlinked to `~/.hammerspoon/silverware-drawer.lua`.
- `install.sh` / `uninstall.sh` — fzf picker, symlinks, per-machine config.
- `spoons/PullMyMainFinger.spoon/refresh-default-branches.sh` — standalone bash logic behind that spoon.

## Spoon contract

- Standard Spoon table (`obj.name`, `version`, `author`, `homepage`, `license`).
- Uniform `:start()` / `:stop()`. `:stop()` must release every watcher, timer, hotkey, and task `:start()` created.
- Options are plain fields on the spoon object; the loader assigns config `opts` onto it **before** `:start()`. Read them at `:start()` time, not module load.
- Errors in one spoon must not break others (loader `pcall`s each; actions inside a spoon should too).

## Rules

- Machine-specific state (enabled set, paths, socket) never goes in the repo — it lives in `~/.hammerspoon/silverware-drawer.config.lua`, which is generated and uncommitted.
- Installer and uninstaller must stay idempotent; re-running converges on the same state.
- Adding a spoon: create `spoons/<Name>.spoon/{init.lua,README.md}`, add a row to the README table. The installer discovers spoons by directory; no registry to edit.
- Changing a spoon's behavior or options: update its `README.md` in the same commit.
- Long-running work goes off the main thread (`hs.task`); Hammerspoon's main thread must not block.

## Verifying

- No test suite. Reload Hammerspoon (`hs -c 'hs.reload()'`) and watch the console (`hs -c` or the Console window) for `[silverware-drawer]` lines.
- Shell scripts: `shellcheck` and run directly (e.g. `PROJECTS_ROOT=<scratch dir> ./spoons/PullMyMainFinger.spoon/refresh-default-branches.sh`) against a throwaway tree, never real repos, when changing git-mutating logic.
