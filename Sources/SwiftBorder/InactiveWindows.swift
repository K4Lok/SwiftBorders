import Cocoa

// Draws dimmer borders on every non-focused normal window. The active window
// is tracked precisely via Accessibility; the inactive set is enumerated from
// the window server (CGWindowList) and reconciled on focus changes + a light
// timer. Inactive borders don't need frame-perfect tracking.
final class InactiveWindows {
    private var pool: [CGWindowID: OverlayWindow] = [:]

    func clear() {
        for (_, win) in pool { win.orderOut(nil) }
        pool.removeAll()
    }

    func refresh(config: BorderConfig) {
        guard config.drawInactive else { clear(); return }

        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1
        let ourPID = getpid()
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return
        }

        let color = NSColor.fromHex(config.inactiveColor)
        var frames: [CGWindowID: CGRect] = [:]
        var skippedActive = false
        // Rects (top-left coords) of every window we've already seen further
        // front. A window whose on-screen area is almost entirely covered by
        // these is hidden — e.g. anything behind a fullscreen/zoomed window — so
        // it gets no border.
        var coveringRects: [CGRect] = []
        let screens = screenRectsTopLeft()

        // CGWindowList is ordered front-to-back; the first normal window owned
        // by the frontmost app is the active one (drawn via AX), so skip it.
        for w in info {
            guard let layer = (w[kCGWindowLayer as String] as? NSNumber)?.intValue, layer == 0,
                  let pid = (w[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, pid != ourPID,
                  let wid = (w[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let boundsDict = w[kCGWindowBounds as String] as? [String: Any]
            else { continue }

            let alpha = (w[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            if alpha <= 0.01 { continue }

            var topLeft = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(boundsDict as CFDictionary, &topLeft) else { continue }
            if topLeft.width < 40 || topLeft.height < 40 { continue }

            // How much of this window's on-screen area is still uncovered by
            // windows in front of it. Near zero → hidden (behind a fullscreen
            // window) → no border.
            let visible = visibleFraction(of: topLeft, screens: screens, front: coveringRects)
            coveringRects.append(topLeft)   // it can still occlude windows behind it

            if pid == frontPID && !skippedActive {
                skippedActive = true
                continue
            }
            // Hidden windows get no border unless the user opts in.
            if !config.drawHiddenWindows && visible < 0.06 { continue }
            frames[wid] = Geometry.cocoaRect(fromTopLeft: topLeft)
        }

        for (wid, win) in pool where frames[wid] == nil {
            win.orderOut(nil)
            pool[wid] = nil
        }
        for (wid, frame) in frames {
            let win = pool[wid] ?? {
                let created = OverlayWindow()
                pool[wid] = created
                return created
            }()
            // Match the active border exactly except for color: use the same
            // per-window radius the WindowServer reports (falling back to the
            // configured radius if detection is unavailable).
            var effective = config
            if let detected = WindowRadius.cornerRadius(ofWindowID: wid) {
                effective.cornerRadius = detected
            }
            effective.opacity = config.inactiveOpacity   // inactive has its own opacity
            if !config.animateAll { effective.animation = "none" } // animations are active-window only unless opted in
            win.update(frame: frame, config: effective, color: color)
        }
    }

    // Screen frames in CGWindowList's top-left coordinate space (y down from the
    // primary display's top), so they can be compared directly with window
    // bounds.
    private func screenRectsTopLeft() -> [CGRect] {
        let ph = Geometry.primaryHeight
        return NSScreen.screens.map { s in
            let f = s.frame
            return CGRect(x: f.origin.x, y: ph - f.origin.y - f.height, width: f.width, height: f.height)
        }
    }

    // Fraction of `rect`'s on-screen area not covered by any `front` rect, via a
    // coarse point grid. Off-screen samples are ignored, so a window that spills
    // past the screen (or past the covering window) is still judged only on its
    // visible part. Returns 0 when the window is fully off-screen.
    private func visibleFraction(of rect: CGRect, screens: [CGRect], front: [CGRect]) -> CGFloat {
        let n = 16
        var onScreen = 0, covered = 0
        for i in 0..<n {
            for j in 0..<n {
                let p = CGPoint(x: rect.minX + (CGFloat(i) + 0.5) / CGFloat(n) * rect.width,
                                y: rect.minY + (CGFloat(j) + 0.5) / CGFloat(n) * rect.height)
                guard screens.contains(where: { $0.contains(p) }) else { continue }
                onScreen += 1
                if front.contains(where: { $0.contains(p) }) { covered += 1 }
            }
        }
        guard onScreen > 0 else { return 0 }
        return CGFloat(onScreen - covered) / CGFloat(onScreen)
    }
}
