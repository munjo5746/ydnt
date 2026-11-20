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
    var freeBefore: Double? = nil   // disk free fraction around the run; same on every entry of a run
    var freeAfter: Double? = nil
    var trashedTo: String? = nil    // set when it went to the Trash instead of being deleted
    var name: String { (path as NSString).lastPathComponent }
}

/// Every deletion ever made, newest first, in a JSON file in Application Support.
@MainActor @Observable
final class History {
    private(set) var entries: [HistoryEntry]
    private let file: URL
    static let keepDays = 90

    struct Run: Identifiable {
        let id: UUID
        let entries: [HistoryEntry]
        var date: Date { entries.first?.date ?? .distantPast }
        var auto: Bool { entries.first?.auto ?? false }
        var freed: Int64 { entries.filter { $0.error == nil }.reduce(0) { $0 + $1.bytes } }
        var succeeded: [HistoryEntry] { entries.filter { $0.error == nil } }
        var failures: [HistoryEntry] { entries.filter { $0.error != nil } }
        var failed: Int { failures.count }
        var trashed: Bool { entries.contains { $0.trashedTo != nil } }
        var places: [String] { entries.map(\.source).reduce(into: []) { if !$0.contains($1) { $0.append($1) } } }
        var freeBefore: Double? { entries.first?.freeBefore }
        var freeAfter: Double? { entries.first?.freeAfter }
    }

    init(file: URL = .applicationSupportDirectory.appending(path: "YouDontNeedThat/history.json")) {
        self.file = file
        entries = Self.recent((try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode([HistoryEntry].self, from: $0) } ?? [])
    }

    private static func recent(_ e: [HistoryEntry], now: Date = .now) -> [HistoryEntry] {
        let cutoff = now.addingTimeInterval(-Double(keepDays) * 86_400)
        return e.filter { $0.date >= cutoff }
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
        entries = Self.recent(new.reversed() + entries)
        save()
    }

    func remove(run: UUID) {
        entries.removeAll { $0.run == run }
        save()
    }

    /// One line per item, oldest first.
    var csv: String {
        func q(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        let rows = entries.reversed().map { e in
            [e.date.ISO8601Format(), e.auto ? "auto" : "manual", e.trashedTo == nil ? "deleted" : "trashed",
             q(e.source), q(e.path), String(e.bytes), q(e.error ?? "")].joined(separator: ",")
        }
        return (["date,by,method,place,path,bytes,error"] + rows).joined(separator: "\n") + "\n"
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
