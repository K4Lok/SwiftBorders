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
    @Published var opacity: Double { didSet { commit() } }
    @Published var dashed: Bool { didSet { commit() } }
    @Published var glow: Bool { didSet { commit() } }
    @Published var glowRadius: Double { didSet { commit() } }
    @Published var outwardBias: Double { didSet { commit() } }
    @Published var launchAtLogin: Bool { didSet { commit() } }

    var onCommit: ((BorderConfig) -> Void)?
    private var isLoading = false

    init(config: BorderConfig) {
        activeColor = Color(nsColor: .fromHex(config.activeColor))
        drawInactive = config.drawInactive
        inactiveColor = Color(nsColor: .fromHex(config.inactiveColor))
        width = config.width
        cornerRadius = config.cornerRadius
        plainCornerRadius = config.plainCornerRadius
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

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    let configURL: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SwiftBorder").font(.headline)

            ColorPicker("Active color", selection: $model.activeColor, supportsOpacity: true)

            Toggle("Border on inactive windows", isOn: $model.drawInactive)
            ColorPicker("Inactive color", selection: $model.inactiveColor, supportsOpacity: true)
                .disabled(!model.drawInactive)

            Divider()

            slider("Width", value: $model.width, range: 0...12, suffix: "pt")
            slider("Corner radius (toolbar)", value: $model.cornerRadius, range: 0...24, suffix: "pt")
            slider("Corner radius (plain)", value: $model.plainCornerRadius, range: 0...24, suffix: "pt")
            slider("Opacity", value: $model.opacity, range: 0...1, suffix: "")
            slider("Outward bias", value: $model.outwardBias, range: 0...1, suffix: "")

            Toggle("Dashed", isOn: $model.dashed)
            Toggle("Glow", isOn: $model.glow)
            slider("Glow radius", value: $model.glowRadius, range: 0...20, suffix: "pt")
                .disabled(!model.glow)

            Divider()

            Toggle("Launch at login", isOn: $model.launchAtLogin)

            HStack {
                Button("Reveal config") {
                    NSWorkspace.shared.activateFileViewerSelecting([configURL])
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .padding(.top, 4)
        }
        .padding(16)
        .frame(width: 300)
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

// Owns the status-bar item and the settings popover.
final class MenuBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let model: SettingsModel

    init(store: ConfigStore) {
        model = SettingsModel(config: store.config)
        super.init()

        model.onCommit = { [weak store] config in store?.commitFromUI(config) }

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "rectangle.dashed",
                                   accessibilityDescription: "SwiftBorder")
                ?? NSImage(systemSymbolName: "rectangle", accessibilityDescription: "SwiftBorder")
            button.imagePosition = .imageOnly
            button.action = #selector(togglePopover)
            button.target = self
        }

        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: SettingsView(model: model, configURL: store.url))
    }

    // Refresh controls after an external edit to the config file.
    func update(_ config: BorderConfig) {
        model.load(config)
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}
