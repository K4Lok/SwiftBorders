import Cocoa
import ApplicationServices

// Reads a window's exact corner radius straight from the WindowServer.
//
// The public Accessibility API doesn't expose corner radius, so — like
// JankyBorders — we ask SkyLight via private symbols. Everything here is
// resolved with dlsym and guarded: if any symbol is missing on a future macOS,
// `cornerRadius(of:)` returns nil and the caller falls back to its configured
// radius. The app keeps working; it just loses pixel-perfect corners.
enum WindowRadius {
    private typealias AXGetWindowFn = @convention(c) (AXUIElement, UnsafeMutablePointer<UInt32>) -> Int32
    private typealias MainConnIDFn = @convention(c) () -> Int32
    private typealias QueryWindowsFn = @convention(c) (Int32, CFArray, UInt32) -> Unmanaged<AnyObject>?
    private typealias QueryCopyFn = @convention(c) (AnyObject) -> Unmanaged<AnyObject>?
    private typealias IterCountFn = @convention(c) (AnyObject) -> Int32
    private typealias IterAdvanceFn = @convention(c) (AnyObject) -> Bool
    private typealias IterRadiiFn = @convention(c) (AnyObject) -> Unmanaged<CFArray>?

    // Resolved once. If `available` is false, detection is permanently off.
    private static let syms: Syms? = Syms()

    private struct Syms {
        let axGetWindow: AXGetWindowFn
        let mainConnID: MainConnIDFn
        let queryWindows: QueryWindowsFn
        let queryCopy: QueryCopyFn
        let iterCount: IterCountFn
        let iterAdvance: IterAdvanceFn
        let iterRadii: IterRadiiFn

        init?() {
            // SkyLight & HIServices are already loaded into the process by Cocoa,
            // so RTLD_DEFAULT finds these. dlopen SkyLight explicitly as a backstop.
            let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)
            let skylight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)

            func resolve(_ name: String) -> UnsafeMutableRawPointer? {
                dlsym(rtldDefault, name) ?? skylight.flatMap { dlsym($0, name) }
            }
            guard let ax = resolve("_AXUIElementGetWindow"),
                  let mc = resolve("SLSMainConnectionID"),
                  let qw = resolve("SLSWindowQueryWindows"),
                  let qc = resolve("SLSWindowQueryResultCopyWindows"),
                  let ic = resolve("SLSWindowIteratorGetCount"),
                  let ia = resolve("SLSWindowIteratorAdvance"),
                  let ir = resolve("SLSWindowIteratorGetCornerRadii") else { return nil }

            axGetWindow = unsafeBitCast(ax, to: AXGetWindowFn.self)
            mainConnID = unsafeBitCast(mc, to: MainConnIDFn.self)
            queryWindows = unsafeBitCast(qw, to: QueryWindowsFn.self)
            queryCopy = unsafeBitCast(qc, to: QueryCopyFn.self)
            iterCount = unsafeBitCast(ic, to: IterCountFn.self)
            iterAdvance = unsafeBitCast(ia, to: IterAdvanceFn.self)
            iterRadii = unsafeBitCast(ir, to: IterRadiiFn.self)
        }
    }

    static var available: Bool { syms != nil }

    // The window's corner radius in points, or nil if it can't be determined.
    static func cornerRadius(of window: AXUIElement) -> Double? {
        guard let s = syms else { return nil }
        var wid: UInt32 = 0
        guard s.axGetWindow(window, &wid) == 0, wid != 0 else { return nil }
        return cornerRadius(ofWindowID: wid)
    }

    // Same query straight from a CGWindowID — used for inactive windows, which
    // are enumerated from CGWindowList and have no AXUIElement handle.
    static func cornerRadius(ofWindowID wid: CGWindowID) -> Double? {
        guard let s = syms, wid != 0 else { return nil }

        let cid = s.mainConnID()
        var widValue = Int32(bitPattern: wid)
        guard let number = CFNumberCreate(nil, .sInt32Type, &widValue) else { return nil }
        let targets = [number] as CFArray

        guard let query = s.queryWindows(cid, targets, 0)?.takeRetainedValue() else { return nil }
        guard let iterator = s.queryCopy(query)?.takeRetainedValue() else { return nil }
        guard s.iterCount(iterator) > 0, s.iterAdvance(iterator) else { return nil }
        // Array is [topLeft, topRight, bottomLeft, bottomRight] — uniform in practice.
        guard let radii = s.iterRadii(iterator)?.takeRetainedValue() as? [NSNumber],
              let first = radii.first else { return nil }

        return first.doubleValue
    }
}
