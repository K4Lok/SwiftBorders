import Cocoa

// A transparent, click-through window that draws one rounded-rect border.
// Reused for both the active window and each inactive window.
final class OverlayWindow: NSWindow {
    private let borderLayer = CAShapeLayer()

    init() {
        super.init(
            contentRect: .zero,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        let view = NSView(frame: .zero)
        view.wantsLayer = true
        view.layer?.addSublayer(borderLayer)
        contentView = view
    }

    // `frame` is the target window's rect in Cocoa (bottom-left) screen coords.
    func update(frame: CGRect, config: BorderConfig, color: NSColor) {
        let width = CGFloat(config.width)
        let pad = width * CGFloat(config.outwardBias)
        // Extra room so a glow/shadow isn't clipped by the window bounds.
        let extra = config.glow ? CGFloat(config.glowRadius) + width : 0
        let totalPad = pad + extra

        let outer = frame.insetBy(dx: -totalPad, dy: -totalPad)
        setFrame(outer, display: true)

        let bounds = CGRect(origin: .zero, size: outer.size)
        // Where the target window sits inside our padded bounds, then outset
        // by `pad` so the stroke frames the window from outside.
        let windowRect = CGRect(x: totalPad, y: totalPad, width: frame.width, height: frame.height)
        let strokeRect = windowRect.insetBy(dx: -pad, dy: -pad)
        let radius = CGFloat(config.cornerRadius) + pad
        let path = CGPath(roundedRect: strokeRect, cornerWidth: radius, cornerHeight: radius, transform: nil)

        let stroke = color.withAlphaComponent(color.alphaComponent * CGFloat(config.opacity))

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        borderLayer.frame = bounds
        borderLayer.path = path
        borderLayer.lineWidth = width
        borderLayer.fillColor = NSColor.clear.cgColor
        borderLayer.strokeColor = stroke.cgColor
        borderLayer.lineDashPattern = config.style == "dashed"
            ? [NSNumber(value: Double(width) * 2), NSNumber(value: Double(width) * 1.5)]
            : nil
        if config.glow {
            borderLayer.shadowColor = color.cgColor
            borderLayer.shadowRadius = CGFloat(config.glowRadius)
            borderLayer.shadowOpacity = 1.0
            borderLayer.shadowOffset = .zero
            borderLayer.masksToBounds = false
        } else {
            borderLayer.shadowOpacity = 0
        }
        CATransaction.commit()

        // This window only ever serves one display, so a plain
        // orderFrontRegardless (which shows without activating our background
        // .accessory app) lands on the correct Space.
        if !isVisible {
            orderFrontRegardless()
            dlog("overlay show frame=\(rectStr(outer))")
        }
    }

    func hideBorder() {
        if isVisible { orderOut(nil) }
    }
}
