import SwiftUI
import AppKit
import QuartzCore

// Observable mirror of BorderConfig for SwiftUI bindings. Any edit commits the
// whole config back through `onCommit`. `load(_:)` updates the controls from an
// external file edit without re-triggering a commit (guarded by `isLoading`).
final class SettingsModel: ObservableObject {
    @Published var activeColor: Color { didSet { commit() } }
    @Published var drawInactive: Bool { didSet { commit() } }
    @Published var inactiveColor: Color { didSet { commit() } }
    @Published var inactiveOpacity: Double { didSet { commit() } }
    @Published var drawHiddenWindows: Bool { didSet { commit() } }
    @Published var width: Double { didSet { commit() } }
    @Published var cornerRadius: Double { didSet { commit() } }
    @Published var plainCornerRadius: Double { didSet { commit() } }
    @Published var cornerSmoothing: Double { didSet { commit() } }
    @Published var opacity: Double { didSet { commit() } }
    @Published var dashed: Bool { didSet { commit() } }
    @Published var glow: Bool { didSet { commit() } }
    @Published var glowRadius: Double { didSet { commit() } }
    @Published var outwardBias: Double { didSet { commit() } }
    @Published var animation: String { didSet { commit() } }
    @Published var animationDuration: Double { didSet { commit() } }
    @Published var beamPalette: String { didSet { commit() } }
    @Published var beamColor: Color { didSet { commit() } }
    @Published var beamSize: Double { didSet { commit() } }
    @Published var animateAll: Bool { didSet { commit() } }
    @Published var launchAtLogin: Bool { didSet { commit() } }

    // Usable height of the screen the menu-bar icon lives on. Set by the
    // controller right before the popover opens so the scroll area can be capped
    // to fit below the menu bar (not a persisted setting).
    @Published var availableHeight: CGFloat = 800

    var onCommit: ((BorderConfig) -> Void)?
    private var isLoading = false

    init(config: BorderConfig) {
        activeColor = Color(nsColor: .fromHex(config.activeColor))
        drawInactive = config.drawInactive
        inactiveColor = Color(nsColor: .fromHex(config.inactiveColor))
        inactiveOpacity = config.inactiveOpacity
        drawHiddenWindows = config.drawHiddenWindows
        width = config.width
        cornerRadius = config.cornerRadius
        plainCornerRadius = config.plainCornerRadius
        cornerSmoothing = config.cornerSmoothing
        opacity = config.opacity
        dashed = config.style == "dashed"
        glow = config.glow
        glowRadius = config.glowRadius
        outwardBias = config.outwardBias
        animation = config.animation
        animationDuration = config.animationDuration
        beamPalette = config.beamPalette
        beamColor = Color(nsColor: .fromHex(config.beamColor))
        beamSize = config.beamSize
        animateAll = config.animateAll
        launchAtLogin = config.launchAtLogin
    }

    func load(_ config: BorderConfig) {
        isLoading = true
        activeColor = Color(nsColor: .fromHex(config.activeColor))
        drawInactive = config.drawInactive
        inactiveColor = Color(nsColor: .fromHex(config.inactiveColor))
        inactiveOpacity = config.inactiveOpacity
        drawHiddenWindows = config.drawHiddenWindows
        width = config.width
        cornerRadius = config.cornerRadius
        plainCornerRadius = config.plainCornerRadius
        cornerSmoothing = config.cornerSmoothing
        opacity = config.opacity
        dashed = config.style == "dashed"
        glow = config.glow
        glowRadius = config.glowRadius
        outwardBias = config.outwardBias
        animation = config.animation
        animationDuration = config.animationDuration
        beamPalette = config.beamPalette
        beamColor = Color(nsColor: .fromHex(config.beamColor))
        beamSize = config.beamSize
        animateAll = config.animateAll
        launchAtLogin = config.launchAtLogin
        isLoading = false
    }

    private func commit() {
        guard !isLoading else { return }
        onCommit?(currentConfig())
    }

    private func currentConfig() -> BorderConfig {
        var c = BorderConfig()
        c.width = width
        c.cornerRadius = cornerRadius
        c.plainCornerRadius = plainCornerRadius
        c.cornerSmoothing = cornerSmoothing
        c.activeColor = NSColor(activeColor).hexString
        c.drawInactive = drawInactive
        c.inactiveColor = NSColor(inactiveColor).hexString
        c.inactiveOpacity = inactiveOpacity
        c.drawHiddenWindows = drawHiddenWindows
        c.opacity = opacity
        c.style = dashed ? "dashed" : "solid"
        c.glow = glow
        c.glowRadius = glowRadius
        c.outwardBias = outwardBias
        c.animation = animation
        c.animationDuration = animationDuration
        c.beamPalette = beamPalette
        c.beamColor = NSColor(beamColor).hexString
        c.beamSize = beamSize
        c.animateAll = animateAll
        c.launchAtLogin = launchAtLogin
        return c
    }
}

// A SwiftUI shape backed by the exact same squircle construction the overlay
// strokes, so the preview corner matches what actually gets drawn.
private struct SquircleBorderShape: Shape {
    var cornerRadius: CGFloat
    var smoothing: CGFloat
    func path(in rect: CGRect) -> Path {
        Path(SquirclePath.path(in: rect, cornerRadius: max(cornerRadius, 0), smoothing: smoothing))
    }
}

// Live, faithful mini-window showing the current border style. Animated styles
// are driven by a TimelineView clock so the preview moves like the real overlay.
private struct PreviewSwatch: View {
    @ObservedObject var model: SettingsModel

    private var paletteColors: [Color] {
        let accent = NSColor(model.beamColor)
        return BeamPalette.colors(model.beamPalette, accent: accent).map { Color(nsColor: $0) }
    }

    // Conic "beam": base ring everywhere, brightening through the palette across
    // a wedge of `beamSize`, centered at the top.
    private var beamGradient: Gradient {
        let base = model.activeColor.opacity(model.opacity)
        let span = min(max(model.beamSize, 0.05), 0.9)
        let start = 0.5 - span / 2, end = 0.5 + span / 2
        var stops: [Gradient.Stop] = [.init(color: base, location: 0), .init(color: base, location: start)]
        let pal = paletteColors
        for (i, c) in pal.enumerated() {
            let t = pal.count == 1 ? 0.5 : Double(i) / Double(pal.count - 1)
            stops.append(.init(color: c, location: start + t * span))
        }
        stops.append(.init(color: base, location: end))
        stops.append(.init(color: base, location: 1))
        return Gradient(stops: stops)
    }

    private var ringGradient: Gradient {
        let wheel = paletteColors.count >= 2 ? paletteColors : [model.activeColor, Color(nsColor: NSColor(model.beamColor))]
        return Gradient(colors: wheel + [wheel[0]])
    }

    var body: some View {
        let inset = max(model.width / 2 + (model.glow ? model.glowRadius : 0) + 4, 8)
        let shape = SquircleBorderShape(cornerRadius: model.cornerRadius,
                                        smoothing: model.cornerSmoothing)

        ZStack {
            shape
                .fill(Color(nsColor: .windowBackgroundColor))
                .padding(inset)
            TimelineView(.animation) { _ in
                // Same media clock the overlay animations are anchored to, so the
                // preview and the real borders sweep in lockstep.
                let t = CACurrentMediaTime()
                let phase = (t / max(model.animationDuration, 0.1)).truncatingRemainder(dividingBy: 1)
                border(shape: shape, phase: phase).padding(inset)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 86)
        .background(Color(nsColor: .underPageBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .animation(.easeOut(duration: 0.12), value: model.width)
    }

    @ViewBuilder
    private func border(shape: SquircleBorderShape, phase: Double) -> some View {
        let base = model.activeColor.opacity(model.opacity)
        let style = StrokeStyle(lineWidth: model.width, lineCap: .round, lineJoin: .round,
                                dash: model.dashed && model.animation == "none"
                                    ? [model.width * 2, model.width * 1.5] : [])
        let glow = model.glow ? model.glowRadius : 0

        switch model.animation {
        case "conic":
            shape.stroke(AngularGradient(gradient: beamGradient, center: .center,
                                         angle: .degrees(-phase * 360)), style: style)
                .shadow(color: model.glow ? base : .clear, radius: glow)
        case "gradient":
            shape.stroke(AngularGradient(gradient: ringGradient, center: .center),
                         style: style)
                .shadow(color: model.glow ? base : .clear, radius: glow)
        case "comet":
            let len = min(max(model.beamSize, 0.05), 0.9)
            let beam = (paletteColors.first ?? base)
            ZStack {
                shape.stroke(base, style: style)
                let head = phase, tail = phase - len
                shape.trim(from: max(tail, 0), to: head).stroke(beam, style: style)
                if tail < 0 { shape.trim(from: 1 + tail, to: 1).stroke(beam, style: style) }
            }
            .shadow(color: model.glow ? beam : .clear, radius: glow)
        case "pulse":
            let o = 0.3 + 0.7 * (0.5 + 0.5 * cos(phase * 2 * .pi))
            shape.stroke(base, style: style).opacity(o)
                .shadow(color: model.glow ? base : .clear, radius: glow)
        default:
            shape.stroke(base, style: style)
                .shadow(color: model.glow ? base : .clear, radius: glow)
        }
    }
}

// Native translucent popover-style background (blurs whatever is behind the
// window). Needs the host window to be non-opaque with a clear background.
private struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .popover
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    let configURL: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SwiftBorder")
                .font(.headline)
                .padding(.bottom, 2)

            PreviewSwatch(model: model)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    section("Active border") {
                        ColorPicker("Color", selection: $model.activeColor, supportsOpacity: true)
                        slider("Opacity", value: $model.opacity, range: 0...1, suffix: "")
                    }

                    section("Inactive border") {
                        Toggle("Enable", isOn: $model.drawInactive)
                        VStack(alignment: .leading, spacing: 8) {
                            ColorPicker("Color", selection: $model.inactiveColor, supportsOpacity: true)
                            slider("Opacity", value: $model.inactiveOpacity, range: 0...1, suffix: "")
                            Toggle("Show on hidden windows", isOn: $model.drawHiddenWindows)
                        }
                        .disabled(!model.drawInactive)
                    }

                    section("Size & shape") {
                        slider("Width", value: $model.width, range: 0...12, suffix: "pt")
                        slider("Corner radius (toolbar)", value: $model.cornerRadius, range: 0...24, suffix: "pt")
                        slider("Corner radius (plain)", value: $model.plainCornerRadius, range: 0...24, suffix: "pt")
                        slider("Corner smoothing", value: $model.cornerSmoothing, range: 0...1, suffix: "")
                        slider("Outward bias", value: $model.outwardBias, range: 0...1, suffix: "")
                    }

                    section("Style") {
                        Toggle("Dashed", isOn: $model.dashed)
                            .disabled(model.animation != "none")
                        Toggle("Glow", isOn: $model.glow)
                        slider("Glow radius", value: $model.glowRadius, range: 0...20, suffix: "pt")
                            .disabled(!model.glow)
                    }

                    section("Animation") {
                        Picker("Style", selection: $model.animation) {
                            Text("None").tag("none")
                            Text("Conic beam").tag("conic")
                            Text("Comet").tag("comet")
                            Text("Pulse").tag("pulse")
                            Text("Gradient").tag("gradient")
                        }
                        if ["conic", "comet", "gradient"].contains(model.animation) {
                            Picker("Palette", selection: $model.beamPalette) {
                                Text("Custom").tag("custom")
                                Text("Aurora").tag("aurora")
                                Text("Neon").tag("neon")
                                Text("Ocean").tag("ocean")
                                Text("Sunset").tag("sunset")
                                Text("Mono").tag("mono")
                            }
                            if model.beamPalette == "custom" {
                                ColorPicker("Beam color", selection: $model.beamColor, supportsOpacity: true)
                            }
                        }
                        if ["conic", "comet"].contains(model.animation) {
                            slider("Beam size", value: $model.beamSize, range: 0.05...0.9, suffix: "")
                        }
                        if ["conic", "comet", "pulse"].contains(model.animation) {
                            slider("Duration", value: $model.animationDuration, range: 1...20, suffix: "s")
                        }
                        if model.animation != "none" {
                            Toggle("Apply to all windows", isOn: $model.animateAll)
                        }
                    }

                    section("System") {
                        Toggle("Launch at login", isOn: $model.launchAtLogin)
                    }
                }
                .padding(.trailing, 2)   // breathing room for the scroller
            }
            .frame(height: scrollHeight)
            .scrollIndicators(.automatic)

            Divider()

            HStack {
                Button("Reveal config") {
                    NSWorkspace.shared.activateFileViewerSelecting([configURL])
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 300)
        .background(VisualEffectBackground())
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // Scroll-area height, capped so the whole popover sits below the menu bar.
    // `availableHeight` is the menu-bar screen's usable height (set by the
    // controller); subtract the fixed chrome (title + preview + buttons +
    // padding ≈ 230pt) and a safety margin, then clamp.
    private var scrollHeight: CGFloat {
        let avail = model.availableHeight - 230
        return min(340, max(180, avail))
    }

    private func section<Content: View>(_ title: String,
                                        @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func slider(_ label: String, value: Binding<Double>,
                        range: ClosedRange<Double>, suffix: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                Spacer()
                Text(suffix.isEmpty
                     ? String(format: "%.2f", value.wrappedValue)
                     : "\(Int(value.wrappedValue.rounded())) \(suffix)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: range)
        }
    }
}

// Borderless panels normally can't become key; allow it so controls and the
// color picker behave.
private final class SettingsPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

// Owns the status-bar item and the settings panel.
//
// We use a manually-positioned NSPanel instead of NSPopover: on a notched Mac
// with a full menu bar the status item gets hidden in the overflow, leaving its
// button with no valid on-screen frame. NSPopover then anchors to garbage and
// lands in the wrong place (and gets shoved off the top edge). Positioning a
// panel ourselves — top pinned just under the menu bar, clamped to the screen —
// is deterministic regardless of whether the icon is visible.
final class MenuBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let model: SettingsModel
    private let configURL: URL
    private var panel: NSPanel?
    private var outsideClickMonitor: Any?

    init(store: ConfigStore) {
        model = SettingsModel(config: store.config)
        configURL = store.url
        super.init()

        model.onCommit = { [weak store] config in store?.commitFromUI(config) }

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "rectangle.dashed",
                                   accessibilityDescription: "SwiftBorder")
                ?? NSImage(systemSymbolName: "rectangle", accessibilityDescription: "SwiftBorder")
            button.imagePosition = .imageOnly
            button.action = #selector(toggle)
            button.target = self
        }
    }

    // Refresh controls after an external edit to the config file.
    func update(_ config: BorderConfig) {
        model.load(config)
    }

    @objc private func toggle() {
        if let panel, panel.isVisible { close(); return }
        show()
    }

    private func show() {
        // Where the click happened — the reliable signal for which display's
        // menu bar the icon was on (button.window?.screen reports the main
        // display, not the clicked one).
        let click = NSEvent.mouseLocation
        let screen = menuBarScreen(near: click)
        let visible = screen.visibleFrame
        model.availableHeight = visible.height          // set before first layout so the cap applies

        let host = NSHostingController(
            rootView: SettingsView(model: model, configURL: configURL))
        host.sizingOptions = .preferredContentSize

        let panel = SettingsPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 480),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear            // let the blurred material show
        panel.hasShadow = true
        panel.isMovable = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .popUpMenu
        panel.isReleasedWhenClosed = false

        // Adopt the real SwiftUI content size BEFORE positioning, otherwise the
        // clamp runs against a ~zero width and pins it to the screen edge.
        panel.contentViewController = host
        host.view.layoutSubtreeIfNeeded()
        panel.setContentSize(host.view.fittingSize)

        let size = panel.frame.size
        let topY = visible.maxY - 6                       // a hair below the menu bar
        let x = min(max(click.x - size.width / 2, visible.minX + 8),
                    visible.maxX - size.width - 8)
        panel.setFrameOrigin(NSPoint(x: x, y: topY - size.height))

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()                          // shadow follows the rounded content
        self.panel = panel

        // Click-away to dismiss (popover-like transience). The global monitor
        // only fires for clicks in OTHER apps — not our own status item or the
        // system color picker — so it won't fight the icon toggle or color well.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in self?.close() }
    }

    private func close() {
        if let m = outsideClickMonitor { NSEvent.removeMonitor(m); outsideClickMonitor = nil }
        panel?.orderOut(nil)
        panel = nil
    }

    // The screen the icon was clicked on. The cursor sits on that display's menu
    // bar at click time, so the point under the pointer is the reliable signal —
    // unlike button.window?.screen, which reports the main display.
    private func menuBarScreen(near point: NSPoint) -> NSScreen {
        NSScreen.screens.first { $0.frame.contains(point) }
            ?? statusItem.button?.window?.screen
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }
}
