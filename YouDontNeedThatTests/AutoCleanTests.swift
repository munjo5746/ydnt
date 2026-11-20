import XCTest
@testable import YouDontNeedThat

final class AutoCleanTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000_000)
    private func c(_ name: String, daysAgo: Double) -> Candidate {
        Candidate(url: URL(fileURLWithPath: "/w/\(name)"), modified: now.addingTimeInterval(-daysAgo * 86_400), source: "w")
    }

    func testPlanTakesOldestFirstUntilNeedIsCovered() {
        let sizes = ["a": 50, "b": 30, "c": 100, "d": 10] as [String: Int64]
        let candidates = [c("a", daysAgo: 1), c("b", daysAgo: 10), c("c", daysAgo: 5), c("d", daysAgo: 20)]
        let picks = AutoCleaner.plan(candidates, need: 120) { sizes[$0.lastPathComponent]! }
        XCTAssertEqual(picks.map(\.item.name), ["d", "b", "c"])   // 10 + 30 + 100 ≥ 120, stops before a
        XCTAssertEqual(picks.map(\.item.bytes), [10, 30, 100])
    }

    func testPlanSizesOnlyWhatItTakes() {
        var sized: [String] = []
        let candidates = [c("new", daysAgo: 3), c("old", daysAgo: 8), c("older", daysAgo: 9)]
        let picks = AutoCleaner.plan(candidates, need: 1) { sized.append($0.lastPathComponent); return 5 }
        XCTAssertEqual(picks.map(\.item.name), ["older"])
        XCTAssertEqual(sized, ["older"])
        XCTAssertTrue(AutoCleaner.plan(candidates, need: 0) { _ in 5 }.isEmpty)
    }

    func testNeed() {
        let d = DiskSpace(available: 50, total: 1000)
        XCTAssertEqual(d.need(percent: 10), 50)
        XCTAssertLessThanOrEqual(d.need(percent: 5), 0)
    }

    func testDangerousFoldersRefused() {
        let home = Category.home
        for bad in [URL(fileURLWithPath: "/"), URL(fileURLWithPath: "/Users"), home, home.appending(path: "Library"),
                    home.appending(path: "Documents"), URL(fileURLWithPath: "/System/Library"), URL(fileURLWithPath: "/Applications")] {
            XCTAssertFalse(AutoCleaner.isAllowed(bad), bad.path)
        }
        for ok in [home.appending(path: "Downloads"), home.appending(path: "Library/Caches"),
                   home.appending(path: "Library/Developer/Xcode/DerivedData")] {
            XCTAssertTrue(AutoCleaner.isAllowed(ok), ok.path)
        }
        for c in Category.allCases where c != .largeFiles && c != .homeFolder {
            for root in c.roots { XCTAssertTrue(AutoCleaner.isAllowed(root), "\(c.name) preset: \(root.path)") }
        }
    }

    @MainActor func testHistoryKeepsNewestAndPersists() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "ydnt-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let h = History(file: file)
        func entries(_ run: UUID, _ names: [String]) -> [HistoryEntry] {
            names.map { HistoryEntry(run: run, date: .now, path: "/x/\($0)", bytes: 1, source: "x", auto: true, error: nil) }
        }
        let r1 = UUID(), r2 = UUID(), r3 = UUID()
        h.append(entries(r1, ["a", "b"]))
        h.append(entries(r2, ["c", "d"]))
        XCTAssertEqual(h.entries.map(\.name), ["d", "c", "b", "a"])
        XCTAssertEqual(h.runs.map(\.id), [r2, r1])
        XCTAssertEqual(h.runs[0].entries.map(\.name), ["c", "d"])
        XCTAssertEqual(History(file: file).entries.map(\.name), ["d", "c", "b", "a"])

        // Older than the retention window: dropped on append and on load.
        h.append([HistoryEntry(run: UUID(), date: .now.addingTimeInterval(-91 * 86_400), path: "/x/old", bytes: 1, source: "x", auto: true, error: nil)])
        XCTAssertFalse(h.entries.contains { $0.name == "old" })

        // Undo drops a whole run; CSV has a header plus one line per entry.
        h.remove(run: r2)
        XCTAssertEqual(h.entries.map(\.name), ["b", "a"])
        XCTAssertEqual(h.csv.split(separator: "\n").count, 3)

        // Run splits succeeded/failed; old entries without free-space fields still decode.
        h.append([HistoryEntry(run: r3, date: .now, path: "/x/ok", bytes: 5, source: "x", auto: true, error: nil, freeBefore: 0.08, freeAfter: 0.12),
                  HistoryEntry(run: r3, date: .now, path: "/x/bad", bytes: 7, source: "x", auto: true, error: "nope", freeBefore: 0.08, freeAfter: 0.12)])
        let run = h.runs[0]
        XCTAssertEqual(run.succeeded.map(\.name), ["ok"])
        XCTAssertEqual(run.failures.map(\.name), ["bad"])
        XCTAssertEqual(run.freed, 5)
        XCTAssertEqual(run.freeAfter, 0.12)
        let old = #"[{"id":"\#(UUID())","run":"\#(UUID())","date":0,"path":"/x/y","bytes":1,"source":"x","auto":false}]"#
        let decoded = try JSONDecoder().decode([HistoryEntry].self, from: Data(old.utf8))[0]
        XCTAssertNil(decoded.freeBefore)
        XCTAssertNil(decoded.trashedTo)
    }

    func testPlanSkipsRecentAppleAndRefused() {
        let candidates = [c("fresh", daysAgo: 1), c("com.apple.Safari", daysAgo: 400), c("refused", daysAgo: 300), c("ok", daysAgo: 10)]
        let picks = AutoCleaner.plan(candidates, need: .max, now: now, skip: ["/w/refused"]) { _ in 1 }
        XCTAssertEqual(picks.map(\.item.name), ["ok"])
    }

    func testCachesIgnoreTheRecentRule() {
        let cache = Candidate(url: Category.cachesFolder.appending(path: "com.spotify.client"),
                              modified: now.addingTimeInterval(-3600), source: "Caches")
        let picks = AutoCleaner.plan([cache, c("fresh", daysAgo: 1)], need: .max, now: now) { _ in 1 }
        XCTAssertEqual(picks.map(\.item.name), ["com.spotify.client"])
    }

    func testOldSettingsDecodeWithDefaults() throws {
        let old = #"{"enabled":false,"thresholdPercent":20,"folders":[{"path":"/w"}]}"#
        let s = try JSONDecoder().decode(AutoCleanSettings.self, from: Data(old.utf8))
        XCTAssertFalse(s.enabled)
        XCTAssertEqual(s.thresholdPercent, 20)
        XCTAssertEqual(s.stopPercent, 25)
        XCTAssertFalse(s.askFirst)
        XCTAssertEqual(s.folders, [WatchedFolder(path: "/w", enabled: true)])
    }
}
