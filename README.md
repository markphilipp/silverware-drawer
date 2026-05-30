# be-right-back

`brb` — a macOS daemon that runs automations when you lock and unlock your Mac.

When you step away, your machine should know. Lock the screen and `be-right-back`
fires off whatever you want it to: toggle [Caffeine](https://intelliscapesolutions.com/apps/caffeine),
pause media, mute the mic, flip your status to away. Unlock and it puts everything
back the way you left it.

## Status

🚧 Early days — figuring out the implementation. The first goal is simple:
enable/disable the **Caffeine** app on lock/unlock, then grow into a general
lock-event automation framework.

## How it'll work

macOS broadcasts `com.apple.screenIsLocked` and `com.apple.screenIsUnlocked`
distributed notifications. `be-right-back` listens for these and dispatches to
your configured actions.

Planned ideas:

**On lock (you step away)**
- Toggle Caffeine off
- Pause media (Spotify / Music / browser)
- Mute mic & system audio
- Set Slack/Teams status → away / DND
- Pause downloads & sync clients

**On unlock (you're back)**
- Restore the above

## Implementation

TBD — choosing between a small Swift binary, Hammerspoon, or shell + `launchd`.

## License

TBD
