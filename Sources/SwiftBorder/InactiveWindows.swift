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

            if pid == frontPID && !skippedActive {
                skippedActive = true
                continue
            }
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
            win.update(frame: frame, config: config, color: color)
        }
    }
}
