import Cocoa
import ApplicationServices

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

// Hold strong references so the controller (and the pointer AX holds) and the
// config watcher live for the whole process lifetime.
let controller = BorderController()
let store = ConfigStore()
let menuBar = MenuBarController(store: store)

LaunchAtLogin.apply(store.config.launchAtLogin)
store.onChange = { config in
    controller.applyConfig(config)
    LaunchAtLogin.apply(config.launchAtLogin)
}
store.onExternalEdit = { config in
    menuBar.update(config)
}

FileHandle.standardError.write(Data("SwiftBorder config: \(store.path)\n".utf8))

func ensureAccessibilityThenStart() {
    if Accessibility.promptIfNeeded() {
        controller.start(config: store.config)
        return
    }

    FileHandle.standardError.write(Data("""
    SwiftBorder needs Accessibility permission.
    Grant it in System Settings ▸ Privacy & Security ▸ Accessibility,
    then this process will start automatically. Waiting…
    (If the toggle already looks on, click the menu-bar icon and use
     "Reset & re-grant" to clear a stale permission entry.)

    """.utf8))

    // Poll until the user grants permission, then start.
    let timer = Timer(timeInterval: 1.0, repeats: true) { t in
        if Accessibility.isTrusted {
            t.invalidate()
            controller.start(config: store.config)
        }
    }
    RunLoop.main.add(timer, forMode: .common)
}

ensureAccessibilityThenStart()
app.run()
