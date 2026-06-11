import Cocoa

enum Geometry {
    // Height of the primary display (the one at origin 0,0). AX and
    // CGWindowList both report Y from the top of this display.
    static var primaryHeight: CGFloat {
        NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height
            ?? NSScreen.main?.frame.height
            ?? 0
    }

    // Converts a top-left-origin rect (AX / CGWindowList) to Cocoa's
    // bottom-left-origin screen coordinates.
    static func cocoaRect(fromTopLeft r: CGRect) -> CGRect {
        CGRect(x: r.origin.x,
               y: primaryHeight - r.origin.y - r.height,
               width: r.width,
               height: r.height)
    }

    // The display whose frame contains a Cocoa-coordinate point (e.g. a
    // window's center). Used to tell when the active window crossed monitors.
    static func displayID(containing point: CGPoint) -> CGDirectDisplayID? {
        NSScreen.screens.first { $0.frame.contains(point) }?.displayID
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
