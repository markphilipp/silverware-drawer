import Cocoa

class DisplayMonitor {
    var lastState: String = ""

    func isBuiltinMain() -> Bool {
        CGDisplayIsBuiltin(CGMainDisplayID()) != 0
    }

    func setMenuBarAutoHide(_ hide: Bool) {
        let script = "tell application \"System Events\" to tell dock preferences to set autohide menu bar to \(hide)"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
        process.waitUntilExit()
    }

    func apply() {
        let builtin = isBuiltinMain()
        let state = builtin ? "builtin" : "external"

        guard state != lastState else { return }
        lastState = state

        if builtin {
            log("Built-in display is main — showing menu bar")
            setMenuBarAutoHide(false)
        } else {
            log("External display is main — hiding menu bar")
            setMenuBarAutoHide(true)
        }
    }

    @objc func screenChanged(_ notification: Notification) {
        log("Display configuration changed (\(notification.name.rawValue))")
        // Small delay to let macOS finish reconfiguring
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [self] in
            apply()
        }
    }

    func start() {
        log("Display menu bar monitor started (event-driven)")
        apply()

        // Listen for screen change notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }
}

func log(_ message: String) {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    let timestamp = formatter.string(from: Date())
    print("\(timestamp): \(message)", terminator: "\n")
    fflush(stdout)
}

let app = NSApplication.shared
let monitor = DisplayMonitor()
monitor.start()
app.run()
