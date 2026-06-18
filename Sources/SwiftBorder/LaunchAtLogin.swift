import Foundation
import ServiceManagement

// Login-item registration. As a signed .app we use SMAppService — the modern,
// Apple-blessed path that survives Gatekeeper and shows up under System
// Settings ▸ General ▸ Login Items. We also tear down the legacy LaunchAgent
// plist that earlier raw-binary builds wrote, so upgrading users don't end up
// with two auto-start mechanisms.
enum LaunchAtLogin {
    private static let legacyLabel = "com.swiftborder.agent"

    private static var legacyPlistURL: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LaunchAgents/\(legacyLabel).plist")
    }

    static func apply(_ enabled: Bool) {
        // Always remove the obsolete LaunchAgent plist if present.
        try? FileManager.default.removeItem(at: legacyPlistURL)

        let service = SMAppService.mainApp
        do {
            switch (enabled, service.status) {
            case (true, let status) where status != .enabled:
                try service.register()
            case (false, .enabled):
                try service.unregister()
            default:
                break  // already in the desired state
            }
        } catch {
            // SMAppService only works for a proper signed .app; when running the
            // raw binary via `swift run` this throws, which is fine in dev.
            FileHandle.standardError.write(
                Data("SwiftBorder LaunchAtLogin: \(error.localizedDescription)\n".utf8))
        }
    }
}
