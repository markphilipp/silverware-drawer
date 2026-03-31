# bar-peekaboo

Automatically toggles macOS menu bar visibility based on which display is primary:

- **Built-in (laptop) display is main** → menu bar always visible
- **External display is main** → menu bar always hidden

Reacts instantly to display changes (plug/unplug monitors, switching primary display) using macOS screen-change notifications.

## Requirements

- macOS (tested on Sequoia+)
- Xcode Command Line Tools (`xcode-select --install`)
- Accessibility permissions for System Events (macOS will prompt on first run)

## Install

```sh
git clone https://github.com/markphilipp/bar-peekaboo.git
cd bar-peekaboo
./install.sh
```

This compiles the binary, installs a launch agent, and starts it immediately. It will also start automatically on login.

## Usage

View logs:

```sh
tail -f /tmp/bar-peekaboo.log
```

Stop without uninstalling:

```sh
./stop.sh
```

Restart after stopping:

```sh
launchctl load ~/Library/LaunchAgents/com.bar-peekaboo.plist
```

## Uninstall

```sh
./uninstall.sh
```

## How it works

A small Swift daemon listens for `NSApplication.didChangeScreenParametersNotification`. When the display configuration changes, it checks whether the main display is the built-in screen using `CGDisplayIsBuiltin` and toggles the menu bar auto-hide setting via AppleScript (`System Events` → `dock preferences`).
