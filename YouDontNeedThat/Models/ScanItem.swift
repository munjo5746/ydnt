import Foundation

struct ScanItem: Identifiable, Hashable, Sendable {
    let url: URL
    let bytes: Int64
    var isDirectory = false
    var modified: Date? = nil
    var id: String { url.path(percentEncoded: false) }
    var name: String { url.lastPathComponent }
    /// Never selectable: top-level home folders, and Apple's own caches (macOS refuses to delete those anyway).
    var isProtected: Bool {
        Category.protected.contains { $0.pathComponents == url.pathComponents }
            || (name.hasPrefix("com.apple.") && url.deletingLastPathComponent().pathComponents == Category.cachesFolder.pathComponents)
    }
}

struct CategoryResult: Sendable {
    enum Status: Sendable, Equatable { case scanning, scanned, needsAccess }
    let category: Category
    var status: Status
    var items: [ScanItem]   // sorted largest first
    var bytes: Int64 { items.reduce(0) { $0 + $1.bytes } }
}

/// Mockup data. Used by `--fake` launch argument and previews.
enum Fixtures {
    /// Demo mode: sample scan and history, its own settings, and deletes are simulated (nothing on disk changes).
    static let isFake = ProcessInfo.processInfo.arguments.contains("--fake")

    /// Auto-clean for demo mode: throwaway settings and history with a few sample runs.
    @MainActor static func demoCleaner() -> AutoCleaner {
        let suite = "com.edwardchung.ydnt.demo"
        UserDefaults().removePersistentDomain(forName: suite)
        let history = History(file: FileManager.default.temporaryDirectory.appending(path: "ydnt-demo-\(UUID()).json"))
        func run(_ daysAgo: Double, auto: Bool, trash: Bool = false, _ items: [(String, Double, String)], failed: [String] = []) {
            let id = UUID(), date = Date.now.addingTimeInterval(-daysAgo * 86_400)
            let path = { (p: String) in Category.home.appending(path: p).path(percentEncoded: false) }
            history.append(items.map { p, b, source in
                HistoryEntry(run: id, date: date, path: path(p), bytes: Int64(b), source: source, auto: auto, error: nil,
                             trashedTo: trash ? path(".Trash/" + (p as NSString).lastPathComponent) : nil)
            } + failed.map {
                HistoryEntry(run: id, date: date, path: path("Library/Caches/" + $0), bytes: 0, source: "Caches", auto: auto,
                             error: "You don't have permission to access it.")
            })
        }
        run(18, auto: false, [("Parallels/Windows 10.pvm", 18.4e9, "Large Files")])
        run(9, auto: true, [("Library/Developer/Xcode/DerivedData/ShopKit-gdlqzkfxbc", 2.1e9, "DerivedData"),
                            ("Library/Developer/Xcode/iOS DeviceSupport/iPhone 14 · iOS 16.4", 1.9e9, "iOS DeviceSupport")])
        run(3, auto: false, trash: true, [("Downloads/Xcode_15.3.xip", 3.2e9, "Old Downloads"),
                                          ("Downloads/ubuntu-23.10-desktop-arm64.iso", 2.6e9, "Old Downloads")])
        run(0.2, auto: true, [("Library/Caches/Yarn", 1.21e9, "Caches"), ("Library/Caches/com.figma.Desktop", 812e6, "Caches"),
                              ("Library/Caches/com.tinyspeck.slackmacgap", 604e6, "Caches")],
            failed: ["CloudKit", "FamilyCircle"])
        let c = AutoCleaner(history: history, defaults: UserDefaults(suiteName: suite)!)   // schedule runs; deletes are simulated
        c.settings.thresholdPercent = 5
        c.settings.stopPercent = 15
        c.settings.folders = ["Library/Caches", "Library/Developer/Xcode/DerivedData", "Library/Developer/Xcode/iOS DeviceSupport", "Downloads"]
            .map { WatchedFolder(path: Category.home.appending(path: $0).path(percentEncoded: false)) }
        return c
    }

    static let fake: [CategoryResult] = [
        r(.largeFiles, [("Parallels/Windows 11.pvm/Windows11_ARM.vmdk", 24.5e9), ("Movies/wedding-raw-footage.zip", 11.2e9), ("Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw", 8.0e9)]),
        r(.homeFolder, [(".npm", 20e9), ("Documents", 14.3e9), (".gradle", 4.9e9), (".bun", 2.6e9), ("Desktop", 1.2e9)]),
        r(.xcodeJunk, [("Library/Developer/Xcode/DerivedData", 9.8e9), ("Library/Developer/Xcode/iOS DeviceSupport", 6.1e9), ("Library/Developer/Xcode/Archives", 2.4e9)]),
        r(.caches, [("Library/Caches/com.spotify.client", 4.2e9), ("Library/Caches/Google/Chrome", 2.9e9), ("Library/Caches/com.apple.Music", 1.1e9), ("Library/Caches/Homebrew", 860e6), ("Library/Caches/com.tinyspeck.slackmacgap", 610e6), ("Library/Caches/pip", 340e6), ("Library/Caches/com.microsoft.VSCode.ShipIt", 220e6)]),
        r(.iosBackups, [("Library/Application Support/MobileSync/Backup/00008030-001A", 7.6e9)]),
        r(.oldDownloads, [("Downloads/Xcode_15.4.xip", 3.4e9), ("Downloads/ubuntu-24.04-desktop-arm64.iso", 2.9e9), ("Downloads/Zoom.pkg", 140e6), ("Downloads/scan_0042.pdf", 38e6)]),
        r(.trash, [(".Trash/Final_v3_REAL_final.mov", 2.2e9), (".Trash/old-node_modules", 640e6)]),
        CategoryResult(category: .mailAttachments, status: .needsAccess, items: []),
        r(.logs, [("Library/Logs/DiagnosticReports", 410e6), ("Library/Logs/JetBrains", 180e6), ("Library/Logs/Adobe", 96e6)]),
    ]

    private static func r(_ c: Category, _ files: [(String, Double)]) -> CategoryResult {
        CategoryResult(category: c, status: .scanned,
                       items: files.enumerated().map { i, f in
                           ScanItem(url: Category.home.appending(path: f.0), bytes: Int64(f.1),
                                    modified: .now.addingTimeInterval(-Double(i * 97 + 2) * 86_400))
                       })
    }
}
