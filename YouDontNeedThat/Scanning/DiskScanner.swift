import AppKit

// ponytail: plain blocking file IO on the cooperative pool, 8 categories at once. Fine for one user;
// move to a dedicated thread/queue if the UI ever stutters.
enum DiskScanner {
    private static let keys: Set<URLResourceKey> = [
        .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isDirectoryKey, .contentModificationDateKey,
    ]

    nonisolated static func scan(_ category: Category) -> CategoryResult {
        var items: [ScanItem]
        do {
            switch category.rule {
            case .largeFiles:
                items = largeFiles(under: category.roots[0])
            case .roots:
                items = category.roots.compactMap(item(at:))
            case .children:
                items = try children(of: category.roots[0]).compactMap(item(at:))
            case .staleChildren(let days):
                let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
                items = try children(of: category.roots[0])
                    .filter { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) < cutoff }
                    .compactMap(item(at:))
            case .homeFolders:
                // Library, Downloads and Trash already have their own categories; counting them here too
                // would double the chart.
                items = try FileManager.default.contentsOfDirectory(at: category.roots[0], includingPropertiesForKeys: Array(keys))
                    .filter { !["Library", "Downloads", ".Trash"].contains($0.lastPathComponent) }
                    .compactMap(item(at:))
            }
        } catch let e as CocoaError where e.code == .fileReadNoPermission {
            return CategoryResult(category: category, status: .needsAccess, items: [])
        } catch {
            items = []  // root missing etc. → nothing to reclaim
        }
        items.removeAll { $0.bytes == 0 }
        items.sort { $0.bytes > $1.bytes }
        return CategoryResult(category: category, status: .scanned, items: items)
    }

    /// Everything directly inside a folder the user opened, hidden entries included.
    nonisolated static func contents(of url: URL, in category: Category) -> CategoryResult {
        do {
            var items = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: Array(keys)).compactMap(item(at:))
            items.removeAll { $0.bytes == 0 }
            items.sort { $0.bytes > $1.bytes }
            return CategoryResult(category: category, status: .scanned, items: items)
        } catch let e as CocoaError where e.code == .fileReadNoPermission {
            return CategoryResult(category: category, status: .needsAccess, items: [])
        } catch {
            return CategoryResult(category: category, status: .scanned, items: [])
        }
    }

    static func children(of url: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: Array(keys), options: .skipsHiddenFiles)
    }

    static func item(at url: URL) -> ScanItem? {
        guard let v = try? url.resourceValues(forKeys: keys) else { return nil }
        let bytes = v.isDirectory == true ? directorySize(url) : Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
        return ScanItem(url: url, bytes: bytes, isDirectory: v.isDirectory == true, modified: v.contentModificationDate)
    }

    private static func directorySize(_ url: URL) -> Int64 {
        guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { _, _ in true }) else { return 0 }
        var total: Int64 = 0
        for case let f as URL in e {
            if Task.isCancelled { break }
            guard let v = try? f.resourceValues(forKeys: keys) else { continue }
            total += Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
        }
        return total
    }

    private static func largeFiles(under root: URL) -> [ScanItem] {
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { _, _ in true }) else { return [] }
        var out: [ScanItem] = []
        while let url = e.nextObject() as? URL {
            if Task.isCancelled { break }
            guard let v = try? url.resourceValues(forKeys: keys) else { continue }
            if v.isDirectory == true {
                if e.level == 1, ["Library", ".Trash"].contains(url.lastPathComponent) { e.skipDescendants() }
                continue
            }
            let bytes = Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
            if bytes >= 1 << 30 { out.append(ScanItem(url: url, bytes: bytes, modified: v.contentModificationDate)) }
        }
        return out
    }
}

@MainActor @Observable
final class ScanModel {
    var results: [Category: CategoryResult] = [:]
    var isScanning: Bool { results.values.contains { $0.status == .scanning } }
    var needsAccess: Bool { results.values.contains { $0.status == .needsAccess } }
    private(set) var scannedAt: Date?
    private var task: Task<Void, Never>?

    /// Everything that could go: non-protected items across all categories.
    var reclaimable: Int64 {
        results.values.reduce(0) { $0 + $1.items.filter { !$0.isProtected }.reduce(0) { $0 + $1.bytes } }
    }

    func scanAll() {
        if ProcessInfo.processInfo.arguments.contains("--fake") {
            results = Dictionary(uniqueKeysWithValues: Fixtures.fake.map { ($0.category, $0) })
            scannedAt = .now
            return
        }
        task?.cancel()
        for c in Category.allCases { results[c] = CategoryResult(category: c, status: .scanning, items: []) }
        task = Task {
            await withTaskGroup(of: CategoryResult.self) { group in
                for c in Category.allCases { group.addTask { DiskScanner.scan(c) } }
                for await r in group where !Task.isCancelled { results[r.category] = r }
            }
            if !Task.isCancelled { scannedAt = .now }
        }
    }

    func rescan(_ c: Category) {
        results[c]?.status = .scanning
        Task { results[c] = await Task.detached { DiskScanner.scan(c) }.value }
    }

    static func openFullDiskAccessSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
    }
}
