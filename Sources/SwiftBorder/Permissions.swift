import AppKit
import ApplicationServices

// Accessibility (TCC) permission helpers, shared by startup (main.swift) and the
// settings UI (MenuBar.swift).
//
// Why a "reset & re-grant": macOS binds an Accessibility grant to the app's code
// signature. If the *same bundle id* is ever seen with a *different* signature —
// e.g. an unsigned/ad-hoc build was granted first, then replaced by the signed
// release, or the app is re-signed under a different Team ID — the toggle keeps
// showing "on" while AXIsProcessTrusted() returns false, and the app looks
// broken. `tccutil reset` clears the stale entry so a fresh, correct grant can
// be recorded.
enum Accessibility {
    static var bundleID: String { Bundle.main.bundleIdentifier ?? "com.swiftborder.app" }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    // Returns current trust; shows the system grant prompt if not already trusted.
    @discardableResult
    static func promptIfNeeded() -> Bool {
        let opt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(opt)
    }

    // Opens System Settings ▸ Privacy & Security ▸ Accessibility.
    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // Clears any stale TCC grant for this bundle id, then re-prompts. Recovers the
    // "toggle shows on but app still denied" state described above without the user
    // needing the terminal.
    static func resetAndReprompt() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        task.arguments = ["reset", "Accessibility", bundleID]
        try? task.run()
        task.waitUntilExit()
        promptIfNeeded()
    }
}
