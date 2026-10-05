# WorkFocus

Enables macOS Work Focus while you're active; clears it after five minutes idle.
It also turns Focus on at screen unlock and off at screen lock.

## Setup

Focus is driven through Shortcuts.app. Create two shortcuts, each with a single
**Set Focus** action:

- `Work Focus On` → turn Work on
- `Work Focus Off` → turn Work off

## Options

| Option | Default | Effect |
| --- | --- | --- |
| `idleAfter` | `300` | Seconds idle before Focus is cleared. |
| `checkEvery` | `10` | Seconds between idle checks. |
| `shortcutOn` | `"Work Focus On"` | Shortcut that enables Focus. |
| `shortcutOff` | `"Work Focus Off"` | Shortcut that disables Focus. |
