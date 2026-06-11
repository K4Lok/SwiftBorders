import Foundation
import CoreGraphics

// Enable with: SWIFTBORDER_DEBUG=1 swift run
let debugEnabled = ProcessInfo.processInfo.environment["SWIFTBORDER_DEBUG"] == "1"

func dlog(_ message: @autoclosure () -> String) {
    guard debugEnabled else { return }
    FileHandle.standardError.write(Data(("[SB] " + message() + "\n").utf8))
}

func rectStr(_ r: CGRect) -> String {
    String(format: "(%.0f,%.0f %.0fx%.0f)", r.origin.x, r.origin.y, r.width, r.height)
}
