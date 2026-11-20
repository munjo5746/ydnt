import SwiftUI

/// The one place categories live. Add a case, fill the switches, done.
enum Category: String, CaseIterable, Identifiable, Sendable {
    case largeFiles, homeFolder, xcodeJunk, caches, iosBackups, oldDownloads, trash, mailAttachments, logs

    enum Rule: Sendable {
        case largeFiles                 // every file > 1 GB under ~, skipping ~/Library and ~/.Trash
        case roots                      // each root is one item
        case children                   // each top-level entry of roots[0] is one item
        case staleChildren(days: Int)   // children not modified in N days
        case homeFolders                // each top-level entry of ~, hidden ones too, minus folders other categories cover
    }

    var id: String { rawValue }

    static let home = FileManager.default.homeDirectoryForCurrentUser
    private static func h(_ p: String) -> URL { home.appending(path: p) }

    /// Folders you can look inside but never queue for deletion.
    static let protected: [URL] = [home] + ["Library", "Documents", "Desktop", "Downloads", "Pictures", "Movies",
                                            "Music", "Public", "Applications", "Sites", ".Trash"].map(h)

    var name: String {
        switch self {
        case .largeFiles: "Large Files"
        case .homeFolder: "Home Folder"
        case .xcodeJunk: "Xcode Junk"
        case .caches: "Caches"
        case .iosBackups: "iOS Backups"
        case .oldDownloads: "Old Downloads"
        case .trash: "Trash"
        case .mailAttachments: "Mail Attachments"
        case .logs: "Logs"
        }
    }

    var color: Color {
        switch self {
        case .largeFiles: Color(hex: 0xF87171)
        case .homeFolder: Color(hex: 0x2DD4BF)
        case .xcodeJunk: Color(hex: 0x38BDF8)
        case .caches: Color(hex: 0x818CF8)
        case .iosBackups: Color(hex: 0xF472B6)
        case .oldDownloads: Color(hex: 0xC084FC)
        case .trash: Color(hex: 0xA1A1AA)
        case .mailAttachments: Color(hex: 0x4ADE80)
        case .logs: Color(hex: 0xFBBF24)
        }
    }

    var roots: [URL] {
        switch self {
        case .largeFiles, .homeFolder: [Self.home]
        case .xcodeJunk: ["DerivedData", "iOS DeviceSupport", "Archives"].map { Self.h("Library/Developer/Xcode/\($0)") }
        case .caches: [Self.h("Library/Caches")]
        case .iosBackups: [Self.h("Library/Application Support/MobileSync/Backup")]
        case .oldDownloads: [Self.h("Downloads")]
        case .trash: [Self.h(".Trash")]
        case .mailAttachments: [Self.h("Library/Containers/com.apple.mail/Data/Library/Mail Downloads")]
        case .logs: [Self.h("Library/Logs")]
        }
    }

    var rule: Rule {
        switch self {
        case .largeFiles: .largeFiles
        case .homeFolder: .homeFolders
        case .xcodeJunk: .roots
        case .oldDownloads: .staleChildren(days: 183)
        default: .children
        }
    }

    var displayPath: String {
        switch self {
        case .largeFiles: "~ (anywhere)"
        case .homeFolder: "~"
        case .xcodeJunk: "~/Library/Developer/Xcode"
        default: roots[0].abbreviatedPath
        }
    }
}

extension URL {
    var abbreviatedPath: String { (path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath }
}
