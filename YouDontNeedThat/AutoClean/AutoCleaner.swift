import AppKit
import ServiceManagement
import UserNotifications

struct WatchedFolder: Codable, Hashable, Identifiable, Sendable {
    var path: String
    var enabled = true
    var id: String { path }
    var url: URL { URL(fileURLWithPath: path) }
    var name: String { url.lastPathComponent }

    init(path: String, enabled: Bool = true) {
        self.path = path
        self.enabled = enabled
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        path = try c.decode(String.self, forKey: .path)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }
}

struct AutoCleanSettings: Codable, Equatable {
    var enabled = true
    var thresholdPercent = 10   // starts when free space drops below this
    var stopPercent = 15        // and deletes until it's back at this
    var askFirst = false        // true: wait for an OK from the menu bar or the notification
    var folders: [WatchedFolder] = []

    init() {}

    // Settings saved by older versions lack the newer keys.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        thresholdPercent = try c.decodeIfPresent(Int.self, forKey: .thresholdPercent) ?? 10
        stopPercent = try c.decodeIfPresent(Int.self, forKey: .stopPercent) ?? max(15, thresholdPercent + 5)
        askFirst = try c.decodeIfPresent(Bool.self, forKey: .askFirst) ?? false
        folders = try c.decodeIfPresent([WatchedFolder].self, forKey: .folders) ?? []
    }
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
    let source: String
}

struct Pick: Sendable {
    let item: ScanItem
    let source: String
}

enum CleanState: Equatable {
    case idle, paused, planning
    case low(free: Double)
    case waiting(free: Double, bytes: Int64, count: Int)   // ask-first: a plan is ready, waiting for an OK
    case deleting(done: Int, total: Int, freed: Int64)
    case freed(Int64)
    case stuck(free: Double)

    /// Space is low: the menu bar icon gets its dot.
    var alert: Bool {
        switch self {
        case .low, .waiting, .stuck: true
        default: false
        }
    }

    var detail: String {
        switch self {
        case .idle: "Plenty of space. Checking every 10 minutes."
        case .paused: "Auto-clean is paused."
        case .planning: "Space is low. Picking the oldest files in your watched folders…"
        case .low(let f): "Only \(Self.pct(f)) free. Starting cleanup."
        case .waiting(let f, let b, let n): "Only \(Self.pct(f)) free. \(Theme.plural(n, "old item")) (\(Theme.bytes(b))) can go."
        case .deleting(let d, let t, let b): "Deleting \(d) of \(t). \(Theme.bytes(b)) freed so far."
        case .freed(let b): "Freed \(Theme.bytes(b)). Back above the threshold."
        case .stuck(let f): "Still \(Self.pct(f)) free and nothing left to delete. Add more folders."
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
    private(set) var pending: [Pick] = []   // plan waiting for an OK (ask-first) or the next check (just-do-it)
    private(set) var rechecking = false     // settings changed; a plan-only check is pending or running
    private(set) var checkedSettings = AutoCleanSettings()   // what `state` was computed with
    let history: History

    private var running = false
    private var notified = false            // ask-first: notification sent for the current plan
    private var recheck: Task<Void, Never>?
    private var recheckStarted = ContinuousClock.now
    static let settleDelay = Duration.milliseconds(500)   // quiet time after the last change before re-planning
    static let minChecking = Duration.milliseconds(1300)  // "Checking…" shows at least this long (settle + ~0.8 s)
    private var loop: Task<Void, Never>?
    private static let key = "autoClean"
    private static let skipKey = "autoCleanSkip"
    /// Paths macOS refused to delete. Skipped by later runs instead of failing every time.
    var skip: Set<String> {
        get { Set(defaults.stringArray(forKey: Self.skipKey) ?? []) }
        set { defaults.set(Array(newValue), forKey: Self.skipKey) }
    }

    private let defaults: UserDefaults

    /// `poll: false` skips the 10-minute loop (tests).
    init(history: History = History(), defaults: UserDefaults = .standard, poll: Bool = true) {
        self.history = history
        self.defaults = defaults
        settings = defaults.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode(AutoCleanSettings.self, from: $0) } ?? AutoCleanSettings()
        checkedSettings = settings
        if !settings.enabled { state = .paused }
        // ponytail: fixed 10-minute poll; no wake-from-sleep hook, the next tick catches up.
        guard poll else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.check()
                try? await Task.sleep(for: .seconds(600))
            }
        }
    }

    func refreshDisk() { disk = DiskSpace.current() }

    /// The whole auto-clean pass. `force` runs it even while paused, and without asking first.
    /// `planOnly` (after a settings change) never deletes: it only refreshes `pending` and `state`.
    func check(force: Bool = false, planOnly: Bool = false) async {
        refreshDisk()
        guard !running, settings.enabled || force, let disk else { return }
        checkedSettings = settings
        guard disk.need(percent: settings.thresholdPercent) > 0 else {
            pending = []
            if case .freed = state {} else { state = settings.enabled ? .idle : .paused }
            return
        }
        if settings.askFirst, !force, !planOnly, case .waiting(let f, let b, let n) = state {
            // Already planned; ask once, then wait for the OK.
            if !notified { Self.notifyLow(free: f, bytes: b, count: n); notified = true }
            return
        }
        let need = disk.need(percent: settings.stopPercent)
        running = true
        defer { running = false }

        if planOnly || (settings.askFirst && !force) {
            if !planOnly { state = .planning }
            pending = await plan(need: need)
            let bytes = pending.reduce(0) { $0 + $1.item.bytes }
            state = pending.isEmpty ? .stuck(free: disk.free) : .waiting(free: disk.free, bytes: bytes, count: pending.count)
            notified = planOnly   // in-app change: the user is looking, no need to notify
            if !planOnly, !pending.isEmpty { Self.notifyLow(free: disk.free, bytes: bytes, count: pending.count) }
            return
        }

        state = .low(free: disk.free)
        try? await Task.sleep(for: .seconds(2))   // long enough to see in the menu bar
        state = .planning
        let picks = await plan(need: need)
        pending = []

        let entries = await delete(picks, auto: true)
        let freed = entries.filter { $0.error == nil }.reduce(0) { $0 + $1.bytes }
        if !entries.isEmpty { autoRuns += 1 }
        skip.formUnion(entries.filter { $0.error != nil }.map(\.path))
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

    private func plan(need: Int64) async -> [Pick] {
        let folders = settings.folders.filter { $0.enabled && Self.isAllowed($0.url) }   // also drops ones added before a rule existed
        let skip = skip
        return await Task.detached {
            Self.plan(Self.candidates(folders), need: need, skip: skip, inspect: DiskScanner.inspect)
        }.value
    }

    /// Deletes (or trashes), logs every item to history (failures too). Used by auto-clean and the clean-up sheet.
    /// Works off the main thread: removing a folder like DerivedData touches every file inside it.
    func delete(_ picks: [Pick], auto: Bool, trash: Bool = false) async -> [HistoryEntry] {
        let run = UUID()
        let before = DiskSpace.current()?.free
        var entries: [HistoryEntry] = []
        var freed: Int64 = 0
        for (i, p) in picks.enumerated() {
            let url = p.item.url
            let (error, trashedTo) = await Task.detached { () -> (String?, String?) in
                do {
                    if trash {
                        var out: NSURL?
                        try FileManager.default.trashItem(at: url, resultingItemURL: &out)
                        return (nil, (out as URL?)?.path(percentEncoded: false))
                    }
                    try FileManager.default.removeItem(at: url)
                    return (nil, nil)
                } catch { return (error.localizedDescription, nil) }
            }.value
            if error == nil { freed += p.item.bytes }
            entries.append(HistoryEntry(run: run, date: .now, path: url.path(percentEncoded: false), bytes: p.item.bytes,
                                        source: p.source, auto: auto, error: error, trashedTo: trashedTo))
            if auto { state = .deleting(done: i + 1, total: picks.count, freed: freed) }
        }
        let after = DiskSpace.current()?.free
        for i in entries.indices { entries[i].freeBefore = before; entries[i].freeAfter = after }
        history.append(entries)
        return entries
    }

    /// Puts a trashed run back where it came from and drops it from history. Returns how many came back.
    func undoTrash(run: UUID) async -> Int {
        let moves = history.entries.filter { $0.run == run }.compactMap { e in e.trashedTo.map { ($0, e.path) } }
        let back = await Task.detached {
            moves.filter { (try? FileManager.default.moveItem(atPath: $0.0, toPath: $0.1)) != nil }.count
        }.value
        history.remove(run: run)
        refreshDisk()
        return back
    }

    /// Deletes everything in ~/.Trash. Needs Full Disk Access.
    func emptyTrash() async {
        await Task.detached {
            let fm = FileManager.default
            for url in (try? fm.contentsOfDirectory(at: Category.trashFolder, includingPropertiesForKeys: nil)) ?? [] {
                try? fm.removeItem(at: url)
            }
        }.value
        refreshDisk()
    }

    private func settingsChanged(from old: AutoCleanSettings) {
        if let data = try? JSONEncoder().encode(settings) { defaults.set(data, forKey: Self.key) }
        guard settings.enabled != old.enabled || settings.thresholdPercent != old.thresholdPercent
            || settings.stopPercent != old.stopPercent || settings.askFirst != old.askFirst
            || settings.folders != old.folders else { return }
        if !settings.enabled {
            recheck?.cancel(); rechecking = false
            checkedSettings = settings
            if !running { state = .paused; pending = [] }
            return
        }
        scheduleRecheck()
    }

    /// Settings changed: wait until they settle, then re-plan without deleting.
    /// "Checking…" stays up long enough to read, so the result doesn't flash.
    private func scheduleRecheck() {
        recheck?.cancel()
        if !rechecking { recheckStarted = .now }
        rechecking = true
        recheck = Task { [weak self] in
            try? await Task.sleep(for: Self.settleDelay)
            guard !Task.isCancelled, let self else { return }
            await self.check(planOnly: true)
            try? await Task.sleep(until: self.recheckStarted + Self.minChecking)
            guard !Task.isCancelled else { return }
            self.rechecking = false
        }
    }

    // MARK: Ask-first notification

    nonisolated static let cleanAction = "clean"
    private static let lowCategory = "low"

    static func registerNotifications() {
        let clean = UNNotificationAction(identifier: cleanAction, title: "Clean now")
        UNUserNotificationCenter.current().setNotificationCategories(
            [UNNotificationCategory(identifier: lowCategory, actions: [clean], intentIdentifiers: [])])
    }

    private static func notifyLow(free: Double, bytes: Int64, count: Int) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { ok, _ in
            guard ok else { return }
            let content = UNMutableNotificationContent()
            content.title = "Only \(CleanState.pct(free)) free"
            content.body = "\(Theme.plural(count, "old item")) in your watched folders can go, freeing \(Theme.bytes(bytes))."
            content.categoryIdentifier = lowCategory
            center.add(UNNotificationRequest(identifier: lowCategory, content: content, trigger: nil))
        }
    }

    // MARK: Pure parts

    /// Photos and iPhoto libraries: synced or irreplaceable, never auto-deleted wherever they sit.
    nonisolated static let photoLibraries: Set<String> = ["photoslibrary", "photolibrary"]

    /// Top-level entries of the folders, minus iCloud-synced items and photo libraries.
    nonisolated static func candidates(_ folders: [WatchedFolder]) -> [Candidate] {
        folders.flatMap { f in
            ((try? DiskScanner.children(of: f.url)) ?? []).compactMap { url in
                if photoLibraries.contains(url.pathExtension.lowercased()) { return nil }
                let v = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isUbiquitousItemKey])
                if v?.isUbiquitousItem == true { return nil }
                return Candidate(url: url, modified: v?.contentModificationDate ?? .distantPast, source: f.name)
            }
        }
    }

    /// Anything changed this recently is never auto-deleted, except in ~/Library/Caches:
    /// apps touch their caches constantly, so the rule would leave nothing to clean there.
    nonisolated static let minAge: TimeInterval = 3 * 86_400

    nonisolated static func inCaches(_ url: URL) -> Bool {
        url.deletingLastPathComponent().standardizedFileURL.pathComponents == Category.cachesFolder.standardizedFileURL.pathComponents
    }

    nonisolated static func tooRecent(_ date: Date, _ url: URL, now: Date) -> Bool {
        now.timeIntervalSince(date) < minAge && !inCaches(url)
    }

    /// Oldest first, until `need` bytes are covered. Inspects lazily: only what it takes gets walked.
    /// Never picks: Apple's caches, paths in `skip`, anything changed in the last `minAge` (anywhere inside it,
    /// not just the folder's own date) and anything holding iCloud-synced content.
    // ponytail: ordering uses each entry's own mtime (cheap); the deep check only gates what gets picked.
    nonisolated static func plan(_ candidates: [Candidate], need: Int64, now: Date = .now, skip: Set<String> = [],
                                 inspect: (URL) -> DiskScanner.Inspection) -> [Pick] {
        var picks: [Pick] = []
        var total: Int64 = 0
        let eligible = candidates.filter {
            !tooRecent($0.modified, $0.url, now: now) && !$0.url.lastPathComponent.hasPrefix("com.apple.")
                && !skip.contains($0.url.path(percentEncoded: false))
        }
        for c in eligible.sorted(by: { $0.modified < $1.modified }) where total < need {
            let i = inspect(c.url)
            if i.synced || tooRecent(i.newest, c.url, now: now) { continue }
            total += i.bytes
            picks.append(Pick(item: ScanItem(url: c.url, bytes: i.bytes), source: c.source))
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
        // Nor anything inside the system, or inside synced cloud storage (a delete there deletes in the cloud too),
        // or inside a photo library.
        let systemRoots = ["/System", "/usr", "/bin", "/sbin", "/private", "/Applications"].map { URL(fileURLWithPath: $0).pathComponents }
            + [home.appending(path: "Library/Mobile Documents"), home.appending(path: "Library/CloudStorage")].map(\.pathComponents)
        if p.contains(where: { photoLibraries.contains(($0 as NSString).pathExtension.lowercased()) }) { return false }
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

/// `history(run:)` opens History with that run expanded.
enum Screen: Equatable { case clean, autoClean, history(run: UUID?) }
