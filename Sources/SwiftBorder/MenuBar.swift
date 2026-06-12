import SwiftUI
import AppKit

// Observable mirror of BorderConfig for SwiftUI bindings. Any edit commits the
// whole config back through `onCommit`. `load(_:)` updates the controls from an
// external file edit without re-triggering a commit (guarded by `isLoading`).
final class SettingsModel: ObservableObject {
    @Published var activeColor: Color { didSet { commit() } }
    @Published var drawInactive: Bool { didSet { commit() } }
    @Published var inactiveColor: Color { didSet { commit() } }
    @Published var width: Double { didSet { commit() } }
    @Published var cornerRadius: Double { didSet { commit() } }
    @Published var plainCornerRadius: Double { didSet { commit() } }
    @Published var cornerSmoothing: Double { didSet { commit() } }
    @Published var opacity: Double { didSet { commit() } }
    @Published var dashed: Bool { didSet { commit() } }
    @Published var glow: Bool { didSet { commit() } }
    @Published var glowRadius: Double { didSet { commit() } }
    @Published var outwardBias: Double { didSet { commit() } }
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
        width = config.width
        cornerRadius = config.cornerRadius
        plainCornerRadius = config.plainCornerRadius
        cornerSmoothing = config.cornerSmoothing
        opacity = config.opacity
        dashed = config.style == "dashed"
        glow = config.glow
        glowRadius = config.glowRadius
        outwardBias = config.outwardBias
        launchAtLogin = config.launchAtLogin
    }

    func load(_ config: BorderConfig) {
        isLoading = true
        activeColor = Color(nsColor: .fromHex(config.activeColor))
        drawInactive = config.drawInactive
        inactiveColor = Color(nsColor: .fromHex(config.inactiveColor))
        width = config.width
        cornerRadius = config.cornerRadius
        plainCornerRadius = config.plainCornerRadius
        cornerSmoothing = config.cornerSmoothing
        opacity = config.opacity
        dashed = config.style == "dashed"
        glow = config.glow
        glowRadius = config.glowRadius
        outwardBias = config.outwardBias
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
        c.opacity = opacity
        c.style = dashed ? "dashed" : "solid"
        c.glow = glow
        c.glowRadius = glowRadius
        c.outwardBias = outwardBias
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

// Live, faithful mini-window showing the current border style.
private struct PreviewSwatch: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        // Leave room for half the stroke + the glow so neither gets clipped.
        let inset = max(model.width / 2 + (model.glow ? model.glowRadius : 0) + 4, 8)
        let shape = SquircleBorderShape(cornerRadius: model.cornerRadius,
                                        smoothing: model.cornerSmoothing)
        let stroke = model.activeColor.opacity(model.opacity)

        ZStack {
            shape
                .fill(Color(nsColor: .windowBackgroundColor))
                .padding(inset)
            shape
                .stroke(stroke, style: StrokeStyle(
                    lineWidth: model.width, lineCap: .round, lineJoin: .round,
                    dash: model.dashed ? [model.width * 2, model.width * 1.5] : []))
                .shadow(color: model.glow ? stroke : .clear,
                        radius: model.glow ? model.glowRadius : 0)
                .padding(inset)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 86)
        .background(Color(nsColor: .underPageBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .animation(.easeOut(duration: 0.12), value: model.width)
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
                    section("Color") {
                        ColorPicker("Active", selection: $model.activeColor, supportsOpacity: true)
                        Toggle("Border on inactive windows", isOn: $model.drawInactive)
                        ColorPicker("Inactive", selection: $model.inactiveColor, supportsOpacity: true)
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
                        slider("Opacity", value: $model.opacity, range: 0...1, suffix: "")
                        Toggle("Dashed", isOn: $model.dashed)
                        Toggle("Glow", isOn: $model.glow)
                        slider("Glow radius", value: $model.glowRadius, range: 0...20, suffix: "pt")
                            .disabled(!model.glow)
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
