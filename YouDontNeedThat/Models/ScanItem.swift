import Foundation

struct ScanItem: Identifiable, Hashable, Sendable {
    let url: URL
    let bytes: Int64
    var isDirectory = false
    var id: String { url.path(percentEncoded: false) }
    var name: String { url.lastPathComponent }
    var isProtected: Bool { Category.protected.contains { $0.pathComponents == url.pathComponents } }
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
                       items: files.map { ScanItem(url: Category.home.appending(path: $0.0), bytes: Int64($0.1)) })
    }
}
