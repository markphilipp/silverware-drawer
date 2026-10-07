# BazecorNames

Syncs Bazecor layer, macro, and superkey names between machines. The Dygma
neuron stores keymaps and macro bodies but not names; Bazecor keeps names only in
its local `config.json`. This spoon mirrors just the names through
`iCloud Drive/Bazecor/names.json`, so enable it on every machine that shares the
keyboard. Keymaps, macro bodies, and other settings are never touched.

## Behavior

- A local rename is pushed to `names.json`.
- A rename from another machine is pulled into `config.json`. The pull waits
  until Bazecor is quit, since Bazecor would overwrite the file otherwise.
- If both sides changed between runs, the local side wins.
- The first run on a machine pulls the shared names over its local ones.
- A deferred pull is never lost: nothing is recorded until the pull happens, so
  the next run (Bazecor quitting, a file change, or the timer) retries it.
- Runs on start, when either file changes, when Bazecor quits, and every
  `checkEvery` seconds.
- A corrupt, empty, or oddly shaped `config.json`/`names.json` aborts the run
  with a console error and writes nothing. Writes are atomic and keep the file's
  permissions; a pull changes only the names in `config.json`, nothing else in
  the file.
- Skips while iCloud hasn't downloaded `names.json`. If iCloud Drive's folder is
  missing it does nothing; it only ever creates `Bazecor/` inside it.

Logic lives in `sync.py` (stdlib-only Python 3 run by `python`; the Command Line
Tools provide `/usr/bin/python3`). Run its tests with
`python3 -m unittest discover -s spoons/BazecorNames.spoon -p "test_*.py"`.

## Options

| Option | Default | Effect |
| --- | --- | --- |
| `python` | `"/usr/bin/python3"` | Interpreter that runs `sync.py`. |
| `checkEvery` | `600` | Seconds between fallback syncs. |
| `debounce` | `3` | Seconds to wait after a file change before syncing. |
| `stateFile` | `~/.local/state/bazecor-sync/last-hash` | Per-machine record of the last synced names. Keep it out of iCloud. |
| `configDir` | `~/Library/Application Support/Bazecor` | Folder holding Bazecor's `config.json`. |
| `sharedDir` | `~/Library/Mobile Documents/com~apple~CloudDocs/Bazecor` | Folder holding `names.json`. |

`configDir`, `sharedDir`, and `stateFile` reach `sync.py` as `BAZECOR_CONFIG`,
`BAZECOR_SYNC_FILE`, and `BAZECOR_SYNC_STATE`.
