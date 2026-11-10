import AppKit
import ServiceManagement

struct WatchedFolder: Codable, Hashable, Identifiable, Sendable {
    var path: String
    var minAgeDays: Int
    var id: String { path }
    var url: URL { URL(fileURLWithPath: path) }
    var name: String { url.lastPathComponent }
}

struct AutoCleanSettings: Codable, Equatable {
    var enabled = true
    var thresholdPercent = 10
    var folders: [WatchedFolder] = []
}

struct DiskSpace: Equatable {
    let available: Int64
    let total: Int64
    var free: Double { total > 0 ? Double(available) / Double(total) : 1 }

    static func current() -> DiskSpace? {
        let v = try? Category.home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
        guard let a = v?.volumeAvailableCapacityForImportantUsage, let t = v?.volumeTotalCapacity else { return nil }
        return DiskSpace(available: a, total: Int64(t))
    }

    /// Bytes to delete to get back to `percent` free. ≤ 0 means nothing to do.
    func need(percent: Int) -> Int64 { total * Int64(percent) / 100 - available }
}

/// One top-level entry of a watched folder, before it's sized.
struct Candidate: Sendable {
    let url: URL
    let modified: Date
    let minAgeDays: Int
    let source: String
}

struct Pick: Sendable {
    let item: ScanItem
    let source: String
}

enum CleanState: Equatable {
    case idle, paused, planning
    case low(free: Double)
    case deleting(done: Int, total: Int, freed: Int64)
    case freed(Int64)
    case stuck(free: Double)

    /// Small badge drawn after the menu bar icon. nil = plain icon.
    var badge: String? {
        switch self {
        case .idle: nil
        case .paused: "pause.fill"
        case .planning: "magnifyingglass"
        case .low: "exclamationmark"
        case .deleting: "trash.fill"
        case .freed: "checkmark"
        case .stuck: "exclamationmark.triangle.fill"
        }
    }

    var detail: String {
        switch self {
        case .idle: "Plenty of space. Checking every 10 minutes."
        case .paused: "Auto-clean is paused."
        case .planning: "Space is low. Picking the oldest files in your watched folders…"
        case .low(let f): "Only \(Self.pct(f)) free. Starting cleanup."
        case .deleting(let d, let t, let b): "Deleting \(d) of \(t). \(Theme.bytes(b)) freed so far."
        case .freed(let b): "Freed \(Theme.bytes(b)). Back above the threshold."
        case .stuck(let f): "Still \(Self.pct(f)) free and nothing old enough left to delete. Add folders or lower their age limits."
        }
    }

    var symbol: String {
        switch self {
        case .idle: "checkmark.circle"
        case .paused: "pause.circle"
        case .planning: "magnifyingglass"
        case .low, .stuck: "exclamationmark.triangle"
        case .deleting: "trash"
        case .freed: "sparkles"
        }
    }

    static func pct(_ f: Double) -> String { "\(Int((f * 100).rounded()))%" }
}

@MainActor @Observable
final class AutoCleaner {
    var settings: AutoCleanSettings { didSet { settingsChanged(from: oldValue) } }
    private(set) var state: CleanState = .idle
    private(set) var disk = DiskSpace.current()
    private(set) var autoRuns = 0   // bumps after each auto run that deleted something, so open windows rescan
    var pendingScreen: Screen?       // set by the menu bar panel, consumed by RootView
    let history: History

    private var running = false
    private var loop: Task<Void, Never>?
    private static let key = "autoClean"

    init(history: History = History()) {
        self.history = history
        settings = UserDefaults.standard.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode(AutoCleanSettings.self, from: $0) } ?? AutoCleanSettings()
        if !settings.enabled { state = .paused }
        // ponytail: fixed 10-minute poll; no wake-from-sleep hook, the next tick catches up.
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.check()
                try? await Task.sleep(for: .seconds(600))
            }
        }
    }

    func refreshDisk() { disk = DiskSpace.current() }

    /// The whole auto-clean pass. `force` runs it even while paused.
    func check(force: Bool = false) async {
        refreshDisk()
        guard !running, settings.enabled || force, let disk else { return }
        let need = disk.need(percent: settings.thresholdPercent)
        guard need > 0 else {
            if case .freed = state {} else { state = settings.enabled ? .idle : .paused }
            return
        }
        running = true
        defer { running = false }

        state = .low(free: disk.free)
        try? await Task.sleep(for: .seconds(2))   // long enough to see in the menu bar
        state = .planning
        let folders = settings.folders
        let picks = await Task.detached {
            Self.plan(Self.candidates(folders), need: need) { DiskScanner.item(at: $0)?.bytes ?? 0 }
        }.value

        let entries = await delete(picks, auto: true)
        let freed = entries.filter { $0.error == nil }.reduce(0) { $0 + $1.bytes }
        if !entries.isEmpty { autoRuns += 1 }
        refreshDisk()
        if let d = self.disk, d.need(percent: settings.thresholdPercent) > 0 {
            state = .stuck(free: d.free)
        } else {
            state = .freed(freed)
            Task {
                try? await Task.sleep(for: .seconds(300))
                if case .freed = state { state = settings.enabled ? .idle : .paused }
            }
        }
    }

    /// Permanently deletes, logs every item to history (failures too). Used by auto-clean and the delete list.
    /// Deletes off the main thread: removing a folder like DerivedData touches every file inside it.
    func delete(_ picks: [Pick], auto: Bool) async -> [HistoryEntry] {
        let run = UUID()
        var entries: [HistoryEntry] = []
        var freed: Int64 = 0
        for (i, p) in picks.enumerated() {
            let url = p.item.url
            let error = await Task.detached { () -> String? in
                do { try FileManager.default.removeItem(at: url); return nil } catch { return error.localizedDescription }
            }.value
            if error == nil { freed += p.item.bytes }
            entries.append(HistoryEntry(run: run, date: .now, path: url.path(percentEncoded: false), bytes: p.item.bytes,
                                        source: p.source, auto: auto, error: error))
            if auto { state = .deleting(done: i + 1, total: picks.count, freed: freed) }
        }
        history.append(entries)
        return entries
    }

    private func settingsChanged(from old: AutoCleanSettings) {
        if let data = try? JSONEncoder().encode(settings) { UserDefaults.standard.set(data, forKey: Self.key) }
        guard settings.enabled != old.enabled || settings.thresholdPercent != old.thresholdPercent else { return }
        if !settings.enabled { if !running { state = .paused }; return }
        if !running { state = .idle }
        Task { await check() }
    }

    // MARK: Pure parts

    nonisolated static func candidates(_ folders: [WatchedFolder]) -> [Candidate] {
        folders.flatMap { f in
            ((try? DiskScanner.children(of: f.url)) ?? []).map { url in
                Candidate(url: url,
                          modified: (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast,
                          minAgeDays: f.minAgeDays, source: f.name)
            }
        }
    }

    /// Oldest eligible first, until `need` bytes are covered. Sizes lazily: only what it takes gets measured.
    // ponytail: "oldest" is the entry's own mtime; a folder whose files changed deep inside can look older than it is.
    nonisolated static func plan(_ candidates: [Candidate], need: Int64, now: Date = .now, size: (URL) -> Int64) -> [Pick] {
        var picks: [Pick] = []
        var total: Int64 = 0
        let eligible = candidates
            .filter { $0.modified < now.addingTimeInterval(-Double($0.minAgeDays) * 86_400) }
            .sorted { $0.modified < $1.modified }
        for c in eligible where total < need {
            let bytes = size(c.url)
            total += bytes
            picks.append(Pick(item: ScanItem(url: c.url, bytes: bytes), source: c.source))
        }
        return picks
    }

    /// Refuses folders whose contents are the system, the home folder itself, or anything holding those.
    nonisolated static func isAllowed(_ url: URL) -> Bool {
        let p = url.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let home = Category.home.standardizedFileURL.resolvingSymlinksInPath()
        let protected = [home, home.appending(path: "Library"), home.appending(path: "Documents"), home.appending(path: "Desktop")]
            .map(\.pathComponents)
            + ["/Applications", "/Library", "/System", "/Users", "/Volumes", "/private", "/usr", "/bin", "/sbin", "/opt", "/cores"]
                .map { URL(fileURLWithPath: $0).pathComponents }
        // Watching X deletes X's children, so X may not be a protected folder or any ancestor of one.
        if protected.contains(where: { $0.starts(with: p) }) { return false }
        // Nor anything inside the system.
        let systemRoots = ["/System", "/usr", "/bin", "/sbin", "/private", "/Applications"].map { URL(fileURLWithPath: $0).pathComponents }
        return !systemRoots.contains { p.starts(with: $0) }
    }

    // MARK: Launch at login

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do { try newValue ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister() } catch {
                NSLog("launch at login: \(error)")
            }
        }
    }
}

enum Screen: Equatable { case chart, deleteList, autoClean, history }
