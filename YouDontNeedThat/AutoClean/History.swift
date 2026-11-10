import Foundation

struct HistoryEntry: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    let run: UUID
    let date: Date
    let path: String
    let bytes: Int64
    let source: String      // watched folder or category name
    let auto: Bool
    let error: String?
    var name: String { (path as NSString).lastPathComponent }
}

/// Every deletion ever made, newest first, in a JSON file in Application Support.
@MainActor @Observable
final class History {
    private(set) var entries: [HistoryEntry]
    private let file: URL
    private let cap: Int

    struct Run: Identifiable {
        let id: UUID
        let entries: [HistoryEntry]
        var date: Date { entries.first?.date ?? .distantPast }
        var auto: Bool { entries.first?.auto ?? false }
        var freed: Int64 { entries.filter { $0.error == nil }.reduce(0) { $0 + $1.bytes } }
        var failed: Int { entries.filter { $0.error != nil }.count }
    }

    init(file: URL = .applicationSupportDirectory.appending(path: "YouDontNeedThat/history.json"), cap: Int = 2000) {
        self.file = file
        self.cap = cap
        entries = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode([HistoryEntry].self, from: $0) } ?? []
    }

    /// Runs newest first; entries within a run in the order they were deleted.
    var runs: [Run] {
        var order: [UUID] = []
        var byRun: [UUID: [HistoryEntry]] = [:]
        for e in entries {
            if byRun[e.run] == nil { order.append(e.run) }
            byRun[e.run, default: []].append(e)
        }
        return order.map { Run(id: $0, entries: byRun[$0]!.reversed()) }
    }

    func append(_ new: [HistoryEntry]) {
        guard !new.isEmpty else { return }
        entries = Array((new.reversed() + entries).prefix(cap))
        save()
    }

    func clear() {
        entries = []
        save()
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(entries).write(to: file, options: .atomic)
        } catch {
            NSLog("history save failed: \(error)")
        }
    }
}
