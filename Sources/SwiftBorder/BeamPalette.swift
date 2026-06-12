import Cocoa

// Color palettes for the animated border styles, ported from border-beam's
// presets plus a "custom" two-color case driven by the user's settings.
//
// `colors` returns the bright "beam" colors. The steady ring underneath is the
// configured active color; the beam brightens through these on top.
enum BeamPalette {
    static func colors(_ name: String, accent: NSColor) -> [NSColor] {
        switch name {
        case "aurora":   // emerald → cyan → violet (Solana-style)
            return ["0xff00ffa3", "0xff03e1ff", "0xffdc1fff"].map(NSColor.fromHex)
        case "neon":     // hot pink → purple → indigo → sky (cyberpunk)
            return ["0xfff72585", "0xff7209b7", "0xff4361ee", "0xff4cc9f0"].map(NSColor.fromHex)
        case "sunset":   // coral → amber → magenta
            return ["0xffff512f", "0xfff7567c", "0xffdd2476"].map(NSColor.fromHex)
        case "ocean":    // azure → cyan → aqua
            return ["0xff0072ff", "0xff00c6ff", "0xff6dd5ed"].map(NSColor.fromHex)
        case "mono":     // icy white
            return [NSColor.white]
        default:         // "custom"
            return [accent]
        }
    }

    // Conic-gradient stops for a beam: a steady `base` ring everywhere that
    // brightens through the palette across a wedge of width `size` (fraction of
    // the circle), centered at the top. Returns parallel colors/locations arrays
    // suitable for a CAGradientLayer of type `.conic`.
    static func beamStops(base: NSColor, palette: [NSColor], size: Double)
        -> (colors: [CGColor], locations: [NSNumber]) {
        let span = CGFloat(min(max(size, 0.02), 0.9))
        let start = 0.5 - span / 2
        let end = 0.5 + span / 2

        var colors: [CGColor] = [base.cgColor, base.cgColor]
        var locs: [CGFloat] = [0, start]
        for (i, c) in palette.enumerated() {
            let t = palette.count == 1 ? 0.5 : CGFloat(i) / CGFloat(palette.count - 1)
            colors.append(c.cgColor)
            locs.append(start + t * span)
        }
        colors.append(base.cgColor); locs.append(end)
        colors.append(base.cgColor); locs.append(1)
        return (colors, locs.map { NSNumber(value: Double($0)) })
    }

    // Full multicolor ring for the static gradient style: palette spread evenly
    // around the circle, with the first color repeated at the seam so the wrap is
    // continuous.
    static func ringStops(palette: [NSColor]) -> (colors: [CGColor], locations: [NSNumber]) {
        let wheel = palette.count >= 2 ? palette : (palette + palette)
        let n = wheel.count
        var colors = wheel.map { $0.cgColor }
        colors.append(wheel[0].cgColor)
        let locs = (0...n).map { NSNumber(value: Double($0) / Double(n)) }
        return (colors, locs)
    }
}

// Analytic perimeter of the rounded rect (close enough to the continuous-corner
// squircle for sizing a dash that wraps the path exactly once).
func roundedRectPerimeter(_ rect: CGRect, radius: CGFloat) -> CGFloat {
    let r = min(max(radius, 0), min(rect.width, rect.height) / 2)
    let straight = 2 * ((rect.width - 2 * r) + (rect.height - 2 * r))
    return straight + 2 * .pi * r
}
