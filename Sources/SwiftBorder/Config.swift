import Cocoa

// User-editable settings. Persisted as JSON; colors use JankyBorders-style
// 0xAARRGGBB hex strings so the format feels familiar.
struct BorderConfig: Codable, Equatable {
    // Core look
    var width: Double = 4.0
    var cornerRadius: Double = 16.0          // fallback for windows WITH a toolbar (used only if SkyLight detection fails)
    var plainCornerRadius: Double = 11.0     // fallback for windows WITHOUT a toolbar
    var cornerSmoothing: Double = 1.0        // continuous-corner smoothing 0…1 (0 = circular; macOS Tahoe ≈ 1.0, much smoother than iOS's 0.6)
    var activeColor: String = "0xff8093eb"

    // Inactive borders
    var drawInactive: Bool = false
    var inactiveColor: String = "0x80494d64"
    var inactiveOpacity: Double = 1.0
    var drawHiddenWindows: Bool = false      // also outline windows hidden behind others

    // Style extras
    var opacity: Double = 1.0
    var style: String = "solid"        // "solid" | "dashed"
    var glow: Bool = false
    var glowRadius: Double = 6.0
    var outwardBias: Double = 0.5       // 0 = on the edge, 1 = fully outside

    // System
    var launchAtLogin: Bool = false

    init() {}

    // Tolerant decoder: missing keys fall back to defaults, so adding new
    // settings never breaks an older config.json on disk.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = BorderConfig()
        func g<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decode(T.self, forKey: key)) ?? fallback
        }
        width = g(.width, d.width)
        cornerRadius = g(.cornerRadius, d.cornerRadius)
        plainCornerRadius = g(.plainCornerRadius, d.plainCornerRadius)
        cornerSmoothing = g(.cornerSmoothing, d.cornerSmoothing)
        activeColor = g(.activeColor, d.activeColor)
        drawInactive = g(.drawInactive, d.drawInactive)
        inactiveColor = g(.inactiveColor, d.inactiveColor)
        inactiveOpacity = g(.inactiveOpacity, d.inactiveOpacity)
        drawHiddenWindows = g(.drawHiddenWindows, d.drawHiddenWindows)
        opacity = g(.opacity, d.opacity)
        style = g(.style, d.style)
        glow = g(.glow, d.glow)
        glowRadius = g(.glowRadius, d.glowRadius)
        outwardBias = g(.outwardBias, d.outwardBias)
        launchAtLogin = g(.launchAtLogin, d.launchAtLogin)
    }
}

extension NSColor {
    // Parses 0xAARRGGBB, #AARRGGBB, #RRGGBB, etc. Falls back to clear.
    static func fromHex(_ raw: String) -> NSColor {
        var s = raw.lowercased().trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("0x") { s.removeFirst(2) }
        if s.hasPrefix("#") { s.removeFirst() }

        var v: UInt64 = 0
        guard Scanner(string: s).scanHexInt64(&v) else { return .clear }

        let r, g, b, a: UInt64
        if s.count <= 6 {
            a = 0xff; r = (v >> 16) & 0xff; g = (v >> 8) & 0xff; b = v & 0xff
        } else {
            a = (v >> 24) & 0xff; r = (v >> 16) & 0xff; g = (v >> 8) & 0xff; b = v & 0xff
        }
        return NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255,
                       blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255)
    }

    // Serializes to 0xAARRGGBB.
    var hexString: String {
        let c = usingColorSpace(.sRGB) ?? self
        let to255 = { (v: CGFloat) in Int((v * 255).rounded()) }
        return String(format: "0x%02x%02x%02x%02x",
                      to255(c.alphaComponent), to255(c.redComponent),
                      to255(c.greenComponent), to255(c.blueComponent))
    }
}
