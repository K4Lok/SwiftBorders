import Foundation

// Toggles auto-start by writing a LaunchAgent plist. This works for the raw
// binary today; once packaged as a signed .app you'd switch to SMAppService.
enum LaunchAtLogin {
    static let label = "com.swiftborder.agent"

    private static var plistURL: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LaunchAgents/\(label).plist")
    }

    static func apply(_ enabled: Bool) {
        enabled ? install() : remove()
    }

    private static func install() {
        let executable = Bundle.main.executableURL?.path ?? CommandLine.arguments[0]
        let dict: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executable],
            "RunAtLoad": true,
            "KeepAlive": false,
        ]
        let url = plistURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? PropertyListSerialization.data(
            fromPropertyList: dict, format: .xml, options: 0) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private static func remove() {
        try? FileManager.default.removeItem(at: plistURL)
    }
}
