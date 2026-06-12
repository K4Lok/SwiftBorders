import Cocoa

// A transparent, click-through window that draws one rounded-rect border.
// Reused for both the active window and each inactive window.
//
// The border is a *stroked path* (CAShapeLayer), not a CALayer border: a stroke
// has uniform width everywhere, including the corners. A CALayer `borderWidth`
// with a corner radius pinches at the corners (its inner/outer corner curves
// aren't parallel offsets), so the corner reads thinner than the straight edges.
// The exact corner radius comes from the WindowServer (see WindowRadius), so a
// circular rounded rect matches the window — same approach as JankyBorders.
//
// Animated styles (border-beam-inspired) reuse the same stroked path:
//   • conic    — a rotating conic gradient masked to the stroke (beam sweep)
//   • comet    — a short dash that travels the path via lineDashPhase
//   • pulse    — the solid ring breathing in opacity
//   • gradient — a static multicolor conic ring (no motion)
//   • none     — the original solid (or dashed) stroke
//
// To keep an animation running smoothly, layers and animations are built once
// and only rebuilt when the *style* changes (tracked by `styleKey`); ordinary
// move/resize updates push geometry only.
final class OverlayWindow: NSWindow {
    private let borderLayer = CAShapeLayer()   // solid ring (none / pulse / comet base)
    private let gradientLayer = CAGradientLayer() // conic beam / static ring
    private let maskLayer = CAShapeLayer()     // strokes the path; masks the gradient
    private let cometLayer = CAShapeLayer()    // traveling dash segment

    private var styleKey = ""
    private var lastPerimeter: CGFloat = -1
    private var currentAnimation = "none"

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
        view.layer?.masksToBounds = false

        gradientLayer.type = .conic
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 0)   // 12 o'clock seam
        gradientLayer.mask = maskLayer

        for layer in [borderLayer, cometLayer] {
            layer.fillColor = NSColor.clear.cgColor
            layer.lineJoin = .round
            layer.lineCap = .round
        }
        maskLayer.fillColor = NSColor.clear.cgColor
        maskLayer.strokeColor = NSColor.white.cgColor
        maskLayer.lineJoin = .round
        maskLayer.lineCap = .round

        view.layer?.addSublayer(borderLayer)
        view.layer?.addSublayer(gradientLayer)
        view.layer?.addSublayer(cometLayer)
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
        let path = SquirclePath.path(in: strokeRect, cornerRadius: radius, smoothing: CGFloat(config.cornerSmoothing))
        let perimeter = roundedRectPerimeter(strokeRect, radius: radius)

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // A manually-added sublayer doesn't inherit the window's backing scale, so
        // without this it rasterizes at 1x and the upscaled curves blur.
        for layer in [borderLayer, gradientLayer, maskLayer, cometLayer] {
            layer.contentsScale = backingScaleFactor
            layer.frame = bounds
        }
        borderLayer.path = path
        maskLayer.path = path
        cometLayer.path = path
        borderLayer.lineWidth = width
        maskLayer.lineWidth = width
        cometLayer.lineWidth = width

        // Rebuild colors/animations only when the look changes; otherwise we just
        // pushed new geometry and any running animation keeps going.
        let key = Self.styleKey(config: config, color: color, width: width)
        if key != styleKey {
            styleKey = key
            applyStyle(config: config, color: color, width: width, perimeter: perimeter)
            lastPerimeter = perimeter
        } else if currentAnimation == "comet" && abs(perimeter - lastPerimeter) > 0.5 {
            // The comet dash is sized to the perimeter, so a resize needs a fresh
            // pattern + animation (a move alone does not).
            installComet(config: config, perimeter: perimeter)
            lastPerimeter = perimeter
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

    // MARK: - Style

    private static func styleKey(config: BorderConfig, color: NSColor, width: CGFloat) -> String {
        [
            config.animation, config.beamPalette, config.beamColor,
            color.hexString, config.style,
            String(config.opacity), String(config.beamSize),
            String(config.animationDuration), String(Double(width)),
            config.glow ? "g\(config.glowRadius)" : "n",
        ].joined(separator: "|")
    }

    private func applyStyle(config: BorderConfig, color: NSColor, width: CGFloat, perimeter: CGFloat) {
        currentAnimation = config.animation
        let glowColor = color.cgColor

        // Reset everything; each mode re-enables what it needs.
        borderLayer.removeAllAnimations()
        gradientLayer.removeAllAnimations()
        cometLayer.removeAllAnimations()
        borderLayer.isHidden = true
        gradientLayer.isHidden = true
        cometLayer.isHidden = true
        for l in [borderLayer, gradientLayer, cometLayer] { l.shadowOpacity = 0 }

        func applyGlow(_ layer: CALayer) {
            guard config.glow else { return }
            layer.shadowColor = glowColor
            layer.shadowRadius = CGFloat(config.glowRadius)
            layer.shadowOpacity = 1.0
            layer.shadowOffset = .zero
            layer.masksToBounds = false
        }

        let accent = NSColor.fromHex(config.beamColor)
        let palette = BeamPalette.colors(config.beamPalette, accent: accent)

        switch config.animation {
        case "conic":
            gradientLayer.isHidden = false
            gradientLayer.opacity = Float(config.opacity)
            let stops = BeamPalette.beamStops(base: color, palette: palette, size: config.beamSize)
            gradientLayer.colors = stops.colors
            gradientLayer.locations = stops.locations
            applyGlow(gradientLayer)
            // Rotate the conic *gradient* (its endPoint sweeps a circle around the
            // center), NOT the layer transform — rotating the layer would spin its
            // rectangular mask like a windmill. The mask stays put; colors turn.
            let steps = 60
            let pts: [NSValue] = (0...steps).map { i in
                let a = -2 * Double.pi * Double(i) / Double(steps)
                return NSValue(point: NSPoint(x: 0.5 + 0.5 * cos(a), y: 0.5 + 0.5 * sin(a)))
            }
            let spin = CAKeyframeAnimation(keyPath: "endPoint")
            spin.values = pts
            spin.calculationMode = .linear
            spin.duration = max(config.animationDuration, 0.1)
            spin.repeatCount = .infinity
            spin.isRemovedOnCompletion = false
            anchorToGlobalClock(spin, on: gradientLayer)
            gradientLayer.add(spin, forKey: "spin")

        case "gradient":
            gradientLayer.isHidden = false
            gradientLayer.opacity = Float(config.opacity)
            let stops = BeamPalette.ringStops(palette: palette.count >= 2 ? palette : [color, accent])
            gradientLayer.colors = stops.colors
            gradientLayer.locations = stops.locations
            applyGlow(gradientLayer)

        case "comet":
            borderLayer.isHidden = false
            borderLayer.strokeColor = color.withAlphaComponent(color.alphaComponent * CGFloat(config.opacity)).cgColor
            cometLayer.isHidden = false
            cometLayer.opacity = Float(config.opacity)
            cometLayer.strokeColor = (palette.first ?? accent).cgColor
            applyGlow(cometLayer)
            installComet(config: config, perimeter: perimeter)

        case "pulse":
            borderLayer.isHidden = false
            borderLayer.strokeColor = color.withAlphaComponent(color.alphaComponent * CGFloat(config.opacity)).cgColor
            applyGlow(borderLayer)
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 1.0
            pulse.toValue = 0.3
            pulse.duration = max(config.animationDuration / 2, 0.1)
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            pulse.isRemovedOnCompletion = false
            anchorToGlobalClock(pulse, on: borderLayer)
            borderLayer.add(pulse, forKey: "pulse")

        default: // "none"
            borderLayer.isHidden = false
            borderLayer.strokeColor = color.withAlphaComponent(color.alphaComponent * CGFloat(config.opacity)).cgColor
            borderLayer.lineDashPattern = config.style == "dashed"
                ? [NSNumber(value: Double(width) * 2), NSNumber(value: Double(width) * 1.5)]
                : nil
            applyGlow(borderLayer)
        }

        if config.animation != "none" { borderLayer.lineDashPattern = nil }
    }

    // A single dash sized to the whole perimeter, slid around via lineDashPhase,
    // wraps the closed path seamlessly.
    private func installComet(config: BorderConfig, perimeter: CGFloat) {
        cometLayer.removeAnimation(forKey: "comet")
        let span = CGFloat(min(max(config.beamSize, 0.02), 0.9))
        let dash = max(perimeter * span, 1)
        let gap = max(perimeter - dash, 1)
        cometLayer.lineDashPattern = [NSNumber(value: Double(dash)), NSNumber(value: Double(gap))]
        cometLayer.lineDashPhase = 0

        let move = CABasicAnimation(keyPath: "lineDashPhase")
        move.fromValue = 0
        move.toValue = -Double(perimeter)
        move.duration = max(config.animationDuration, 0.1)
        move.repeatCount = .infinity
        move.isRemovedOnCompletion = false
        anchorToGlobalClock(move, on: cometLayer)
        cometLayer.add(move, forKey: "comet")
    }

    // Anchor a repeating animation to the global media clock (phase 0 at media
    // time 0) so every window's beam — and the settings preview, which reads the
    // same clock — sweeps in unison instead of drifting per add-time.
    private func anchorToGlobalClock(_ anim: CAAnimation, on layer: CALayer) {
        anim.beginTime = layer.convertTime(0, from: nil)
    }

    func hideBorder() {
        if isVisible { orderOut(nil) }
    }
}
