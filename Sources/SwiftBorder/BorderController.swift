import Cocoa
import ApplicationServices

// C-compatible trampoline: AX hands us back the `refcon` we registered with,
// which is a pointer to the BorderController instance.
private func axCallback(
    _ observer: AXObserver,
    _ element: AXUIElement,
    _ notification: CFString,
    _ refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    let controller = Unmanaged<BorderController>.fromOpaque(refcon).takeUnretainedValue()
    controller.handle(notification: notification as String, element: element)
}

final class BorderController {
    // One overlay per display. A single NSWindow can't be reliably re-shown on
    // a different display's Space ("Displays have separate Spaces"), so each
    // display gets its own window that never crosses monitors.
    private var overlays: [CGDirectDisplayID: OverlayWindow] = [:]
    private let inactive = InactiveWindows()
    private var inactiveTimer: Timer?

    private var config = BorderConfig()

    // System-wide AX element: the reliable source of "what is focused right
    // now" — works even when yabai changes focus without posting the usual
    // app-activation notifications.
    private let systemWide = AXUIElementCreateSystemWide()
    private var focusTimer: Timer?

    // The app we currently have an AXObserver on (for snappy move/resize).
    private var observedPID: pid_t = 0
    private var appElement: AXUIElement?
    private var observer: AXObserver?
    private var trackedWindow: AXUIElement?
    private var trackedHasToolbar = false
    private var lastFrame: CGRect = .null
    private var lastDisplayID: CGDirectDisplayID?

    private let appNotifications = [
        kAXFocusedWindowChangedNotification,
        kAXMainWindowChangedNotification,
        kAXFocusedUIElementChangedNotification,
        kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification,
        kAXApplicationHiddenNotification,
        kAXApplicationShownNotification,
    ]

    private let windowNotifications = [
        kAXMovedNotification,
        kAXResizedNotification,
        kAXUIElementDestroyedNotification,
    ]

    func start(config: BorderConfig) {
        self.config = config

        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(syncFocus),
                       name: NSWorkspace.didActivateApplicationNotification, object: nil)
        ws.addObserver(self, selector: #selector(syncFocus),
                       name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)

        // Correctness backstop: re-resolve the focused window ~10x/sec. The AX
        // observers below make it feel instant during drags; this poll catches
        // same-app window switches and yabai-driven focus/resize that don't
        // always post notifications. Reads are a few AX calls — negligible CPU.
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.syncFocus()
        }
        RunLoop.main.add(timer, forMode: .common)
        focusTimer = timer

        reconcileInactive()
        logScreens()
        syncFocus()
    }

    private func logScreens() {
        guard debugEnabled else { return }
        for s in NSScreen.screens {
            dlog("screen id=\(s.displayID.map(String.init) ?? "nil") frame=\(rectStr(s.frame)) primary=\(s.frame.origin == .zero)")
        }
    }

    func applyConfig(_ new: BorderConfig) {
        config = new
        lastFrame = .null   // force a redraw with the new style
        renderActive()
        reconcileInactive()
    }

    // MARK: - Focus resolution

    @objc private func syncFocus() {
        guard let (pid, app) = focusedApp() else {
            hideAllOverlays()
            lastFrame = .null
            lastDisplayID = nil
            return
        }
        // Don't disturb the border while our own UI (settings popover / color
        // panel) is focused — keep showing the last real window's border.
        if pid == getpid() { return }

        if pid != observedPID {
            attachObserver(pid: pid, element: app)
        }

        let window = focusedWindow(of: app)
        if !sameElement(window, trackedWindow) {
            setTrackedWindow(window)
            trackedHasToolbar = window.map(windowHasToolbar) ?? false
            lastFrame = .null
            if config.drawInactive { inactive.refresh(config: config) }
        }
        renderActive()
    }

    // AXUIElement '==' is reference identity, which is unreliable across AX
    // queries — two handles to the same window may differ. Use CFEqual.
    private func sameElement(_ a: AXUIElement?, _ b: AXUIElement?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (x?, y?): return CFEqual(x, y)
        default: return false
        }
    }

    private func focusedApp() -> (pid_t, AXUIElement)? {
        var ref: CFTypeRef?
        if AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &ref) == .success,
           let raw = ref, CFGetTypeID(raw) == AXUIElementGetTypeID() {
            let element = raw as! AXUIElement
            var pid: pid_t = 0
            if AXUIElementGetPid(element, &pid) == .success, pid > 0 {
                return (pid, element)
            }
        }
        // Fallback when the system-wide query is momentarily empty.
        if let front = NSWorkspace.shared.frontmostApplication {
            let pid = front.processIdentifier
            return (pid, AXUIElementCreateApplication(pid))
        }
        return nil
    }

    private func focusedWindow(of app: AXUIElement) -> AXUIElement? {
        for attr in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            var ref: CFTypeRef?
            if AXUIElementCopyAttributeValue(app, attr as CFString, &ref) == .success,
               let raw = ref, CFGetTypeID(raw) == AXUIElementGetTypeID() {
                return (raw as! AXUIElement)
            }
        }
        return nil
    }

    // MARK: - Observer wiring

    private func attachObserver(pid: pid_t, element: AXUIElement) {
        teardownObserver()
        observedPID = pid
        appElement = element

        var obs: AXObserver?
        guard AXObserverCreate(pid, axCallback, &obs) == .success, let obs else { return }
        observer = obs

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in appNotifications {
            AXObserverAddNotification(obs, element, name as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
    }

    private func teardownObserver() {
        if let obs = observer {
            if let element = appElement {
                for name in appNotifications {
                    AXObserverRemoveNotification(obs, element, name as CFString)
                }
            }
            if let window = trackedWindow {
                for name in windowNotifications {
                    AXObserverRemoveNotification(obs, window, name as CFString)
                }
            }
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        }
        observer = nil
        appElement = nil
        trackedWindow = nil
        observedPID = 0
    }

    private func setTrackedWindow(_ window: AXUIElement?) {
        if let obs = observer, let old = trackedWindow {
            for name in windowNotifications {
                AXObserverRemoveNotification(obs, old, name as CFString)
            }
        }
        trackedWindow = window
        if let obs = observer, let window {
            let refcon = Unmanaged.passUnretained(self).toOpaque()
            for name in windowNotifications {
                AXObserverAddNotification(obs, window, name as CFString, refcon)
            }
        }
    }

    // MARK: - Rendering

    private func renderActive() {
        guard let window = trackedWindow,
              let frame = windowFrame(window),
              frame.width >= 1, frame.height >= 1,
              let displayID = Geometry.displayID(containing: CGPoint(x: frame.midX, y: frame.midY)) else {
            hideAllOverlays()
            lastFrame = .null
            lastDisplayID = nil
            return
        }

        let target = overlay(for: displayID)
        // Skip redundant redraws (the poll calls this often).
        if frame.equalTo(lastFrame) && displayID == lastDisplayID && target.isVisible { return }
        lastFrame = frame
        lastDisplayID = displayID
        dlog("render cocoaFrame=\(rectStr(frame)) display=\(displayID) fullscreen=\(isFullscreen(window))")

        var effective = config
        if let detected = WindowRadius.cornerRadius(of: window) {
            // Exact radius straight from the WindowServer (per-app correct).
            effective.cornerRadius = detected
            dlog("radius detected=\(detected) (skylight)")
        } else if isFullscreen(window) {
            effective.cornerRadius = 0           // fullscreen windows are square
        } else if !trackedHasToolbar {
            effective.cornerRadius = config.plainCornerRadius
        }
        hideAllOverlays(except: displayID)
        target.update(frame: frame, config: effective, color: NSColor.fromHex(config.activeColor))
    }

    // Lazily created the first time a display becomes active — i.e. while that
    // display is focused — so its first orderFront lands on the correct Space.
    private func overlay(for displayID: CGDirectDisplayID) -> OverlayWindow {
        if let existing = overlays[displayID] { return existing }
        let created = OverlayWindow()
        overlays[displayID] = created
        return created
    }

    private func hideAllOverlays(except keep: CGDirectDisplayID? = nil) {
        for (id, window) in overlays where id != keep {
            window.hideBorder()
        }
    }

    private func isFullscreen(_ window: AXUIElement) -> Bool {
        var ref: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &ref) == .success,
           let n = ref as? NSNumber {
            return n.boolValue
        }
        return false
    }

    // Tahoe gives toolbar windows larger corners than plain ones. The radius
    // isn't readable via AX, so we detect a toolbar and pick between two
    // configured radii. Computed once per focused window (cached).
    private func windowHasToolbar(_ window: AXUIElement) -> Bool {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXChildrenAttribute as CFString, &ref) == .success,
              let children = ref as? [AXUIElement] else { return false }
        for child in children {
            var roleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleRef) == .success,
               let role = roleRef as? String, role == (kAXToolbarRole as String) {
                return true
            }
        }
        return false
    }

    // MARK: - AX event entry point

    func handle(notification: String, element: AXUIElement) {
        switch notification {
        case kAXMovedNotification, kAXResizedNotification:
            renderActive()
        case kAXUIElementDestroyedNotification, kAXWindowMiniaturizedNotification,
             kAXApplicationHiddenNotification:
            hideAllOverlays()
            lastFrame = .null
            lastDisplayID = nil
            syncFocus()
        default:
            syncFocus()
        }
    }

    // MARK: - Geometry

    private func windowFrame(_ window: AXUIElement) -> CGRect? {
        var posValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let posValue, let sizeValue else { return nil }

        var point = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posValue as! AXValue, .cgPoint, &point)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)

        return Geometry.cocoaRect(fromTopLeft: CGRect(origin: point, size: size))
    }

    // MARK: - Inactive borders

    private func reconcileInactive() {
        inactiveTimer?.invalidate()
        inactiveTimer = nil
        guard config.drawInactive else {
            inactive.clear()
            return
        }
        inactive.refresh(config: config)
        let timer = Timer(timeInterval: 0.7, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.inactive.refresh(config: self.config)
        }
        RunLoop.main.add(timer, forMode: .common)
        inactiveTimer = timer
    }
}
