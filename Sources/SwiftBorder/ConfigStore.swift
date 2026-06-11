import Foundation

// Owns the on-disk config.json: creates a default if missing, loads it, and
// watches the file so edits apply live (no restart). Editors that save
// atomically replace the inode, so the watcher re-arms on delete/rename.
final class ConfigStore {
    let url: URL
    private(set) var config: BorderConfig

    // Fired for any change (external file edit or GUI commit) — the engine
    // listens here to repaint.
    var onChange: ((BorderConfig) -> Void)?
    // Fired only for external file edits — the menu-bar GUI listens here to
    // refresh its controls without fighting the user's own edits.
    var onExternalEdit: ((BorderConfig) -> Void)?

    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1
    private var reloadPending = false
    private var writeWork: DispatchWorkItem?

    init() {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SwiftBorder", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("config.json")

        if let loaded = ConfigStore.read(url) {
            config = loaded
        } else {
            config = BorderConfig()
            ConfigStore.write(config, to: url)
        }
        startWatching()
    }

    var path: String { url.path }

    private static func read(_ url: URL) -> BorderConfig? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(BorderConfig.self, from: data)
    }

    private static func write(_ config: BorderConfig, to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(config) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func reload() {
        guard let fresh = ConfigStore.read(url), fresh != config else { return }
        config = fresh
        onChange?(fresh)
        onExternalEdit?(fresh)
    }

    // Called by the GUI. Applies live immediately, persists to disk debounced
    // so a slider drag doesn't write hundreds of times.
    func commitFromUI(_ new: BorderConfig) {
        guard new != config else { return }
        config = new
        onChange?(new)
        writeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            ConfigStore.write(self.config, to: self.url)
        }
        writeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    private func startWatching() {
        fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            // File vanished mid-save; try again shortly.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.startWatching()
            }
            return
        }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .delete, .rename, .revoke],
            queue: .main
        )
        src.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = self.source?.data ?? []
            if flags.contains(.delete) || flags.contains(.rename) || flags.contains(.revoke) {
                self.rearm()
            } else {
                self.debouncedReload()
            }
        }
        src.setCancelHandler { [weak self] in
            if let fd = self?.fd, fd >= 0 { close(fd) }
            self?.fd = -1
        }
        source = src
        src.resume()
    }

    private func rearm() {
        source?.cancel()
        source = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            self.startWatching()
            self.reload()
        }
    }

    private func debouncedReload() {
        guard !reloadPending else { return }
        reloadPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.reloadPending = false
            self?.reload()
        }
    }
}
