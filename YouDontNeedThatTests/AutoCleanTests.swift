import XCTest
@testable import YouDontNeedThat

final class AutoCleanTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000_000)
    private func c(_ name: String, daysAgo: Double, minAge: Int = 0) -> Candidate {
        Candidate(url: URL(fileURLWithPath: "/w/\(name)"), modified: now.addingTimeInterval(-daysAgo * 86_400), minAgeDays: minAge, source: "w")
    }

    func testPlanTakesOldestFirstUntilNeedIsCovered() {
        let sizes = ["a": 50, "b": 30, "c": 100, "d": 10] as [String: Int64]
        let candidates = [c("a", daysAgo: 1), c("b", daysAgo: 10), c("c", daysAgo: 5), c("d", daysAgo: 20)]
        let picks = AutoCleaner.plan(candidates, need: 120, now: now) { sizes[$0.lastPathComponent]! }
        XCTAssertEqual(picks.map(\.item.name), ["d", "b", "c"])   // 10 + 30 + 100 ≥ 120, stops before a
        XCTAssertEqual(picks.map(\.item.bytes), [10, 30, 100])
    }

    func testPlanSkipsTooYoungAndSizesOnlyWhatItTakes() {
        var sized: [String] = []
        let candidates = [c("young", daysAgo: 3, minAge: 7), c("old", daysAgo: 8, minAge: 7), c("older", daysAgo: 9, minAge: 7)]
        let picks = AutoCleaner.plan(candidates, need: 1, now: now) { sized.append($0.lastPathComponent); return 5 }
        XCTAssertEqual(picks.map(\.item.name), ["older"])
        XCTAssertEqual(sized, ["older"])
        XCTAssertTrue(AutoCleaner.plan(candidates, need: 0, now: now) { _ in 5 }.isEmpty)
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
    }

    @MainActor func testHistoryKeepsNewestAndPersists() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "ydnt-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let h = History(file: file, cap: 3)
        func entries(_ run: UUID, _ names: [String]) -> [HistoryEntry] {
            names.map { HistoryEntry(run: run, date: .now, path: "/x/\($0)", bytes: 1, source: "x", auto: true, error: nil) }
        }
        let r1 = UUID(), r2 = UUID()
        h.append(entries(r1, ["a", "b"]))
        h.append(entries(r2, ["c", "d"]))
        XCTAssertEqual(h.entries.map(\.name), ["d", "c", "b"])
        XCTAssertEqual(h.runs.map(\.id), [r2, r1])
        XCTAssertEqual(h.runs[0].entries.map(\.name), ["c", "d"])
        XCTAssertEqual(History(file: file, cap: 3).entries.map(\.name), ["d", "c", "b"])
    }
}
