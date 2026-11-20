import XCTest
@testable import YouDontNeedThat

final class AutoCleanTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000_000)
    private func old(_ bytes: Int64) -> DiskScanner.Inspection { .init(bytes: bytes, newest: .distantPast, synced: false) }

    private func c(_ name: String, daysAgo: Double) -> Candidate {
        Candidate(url: URL(fileURLWithPath: "/w/\(name)"), modified: now.addingTimeInterval(-daysAgo * 86_400), source: "w")
    }

    func testPlanTakesOldestFirstUntilNeedIsCovered() {
        let sizes = ["a": 50, "b": 30, "c": 100, "d": 10] as [String: Int64]
        let candidates = [c("a", daysAgo: 1), c("b", daysAgo: 10), c("c", daysAgo: 5), c("d", daysAgo: 20)]
        let picks = AutoCleaner.plan(candidates, need: 120, now: now) { old(sizes[$0.lastPathComponent]!) }
        XCTAssertEqual(picks.map(\.item.name), ["d", "b", "c"])   // 10 + 30 + 100 ≥ 120, stops before a
        XCTAssertEqual(picks.map(\.item.bytes), [10, 30, 100])
    }

    func testPlanSizesOnlyWhatItTakes() {
        var sized: [String] = []
        let candidates = [c("new", daysAgo: 3), c("old", daysAgo: 8), c("older", daysAgo: 9)]
        let picks = AutoCleaner.plan(candidates, need: 1, now: now) { sized.append($0.lastPathComponent); return old(5) }
        XCTAssertEqual(picks.map(\.item.name), ["older"])
        XCTAssertEqual(sized, ["older"])
        XCTAssertTrue(AutoCleaner.plan(candidates, need: 0, now: now) { _ in old(5) }.isEmpty)
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
        let picks = AutoCleaner.plan(candidates, need: .max, now: now, skip: ["/w/refused"]) { _ in old(1) }
        XCTAssertEqual(picks.map(\.item.name), ["ok"])
    }

    func testCachesIgnoreTheRecentRule() {
        let cache = Candidate(url: Category.cachesFolder.appending(path: "com.spotify.client"),
                              modified: now.addingTimeInterval(-3600), source: "Caches")
        let picks = AutoCleaner.plan([cache, c("fresh", daysAgo: 1)], need: .max, now: now) { _ in
            .init(bytes: 1, newest: self.now, synced: false)   // changed just now, deep inside too
        }
        XCTAssertEqual(picks.map(\.item.name), ["com.spotify.client"])
    }

    /// "Never touched": a folder that looks old but changed deep inside, or holds iCloud content, is skipped.
    func testPlanChecksInsideFolders() {
        let candidates = [c("touched-inside", daysAgo: 90), c("synced", daysAgo: 90), c("really-old", daysAgo: 90)]
        let picks = AutoCleaner.plan(candidates, need: .max, now: now) { url in
            switch url.lastPathComponent {
            case "touched-inside": .init(bytes: 1, newest: self.now.addingTimeInterval(-3600), synced: false)
            case "synced": .init(bytes: 1, newest: .distantPast, synced: true)
            default: self.old(1)
            }
        }
        XCTAssertEqual(picks.map(\.item.name), ["really-old"])
    }

    func testInspectSeesDeepChangesAndSize() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appending(path: "ydnt-\(UUID())")
        let deep = dir.appending(path: "a/b")
        try fm.createDirectory(at: deep, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        try Data(count: 10_000).write(to: deep.appending(path: "fresh.txt"))
        let longAgo = Date.now.addingTimeInterval(-90 * 86_400)
        for p in [dir, dir.appending(path: "a"), deep] { try fm.setAttributes([.modificationDate: longAgo], ofItemAtPath: p.path) }
        let i = DiskScanner.inspect(dir)
        XCTAssertGreaterThan(i.newest, Date.now.addingTimeInterval(-60))   // the folder itself looks 90 days old
        XCTAssertGreaterThanOrEqual(i.bytes, 10_000)
        XCTAssertFalse(i.synced)
    }

    func testCloudAndPhotoFoldersRefused() {
        let home = Category.home
        for bad in [home.appending(path: "Library/Mobile Documents"), home.appending(path: "Library/Mobile Documents/com~apple~CloudDocs/Old"),
                    home.appending(path: "Library/CloudStorage/Dropbox"), home.appending(path: "Pictures/Photos Library.photoslibrary/originals")] {
            XCTAssertFalse(AutoCleaner.isAllowed(bad), bad.path)
        }
        XCTAssertTrue(AutoCleaner.isAllowed(home.appending(path: "Pictures/Screenshots")))
        let lib = Candidate(url: URL(fileURLWithPath: "/w/Photos Library.photoslibrary"), modified: .distantPast, source: "w")
        XCTAssertTrue(AutoCleaner.photoLibraries.contains(lib.url.pathExtension.lowercased()))
    }

    func testNextCheck() {
        XCTAssertEqual(AutoCleaner.nextCheck(last: nil, minutes: 60, now: now), now)                 // never checked: now
        let last = now.addingTimeInterval(-50 * 60)
        XCTAssertEqual(AutoCleaner.nextCheck(last: last, minutes: 60, now: now), now.addingTimeInterval(10 * 60))
        XCTAssertLessThan(AutoCleaner.nextCheck(last: last, minutes: 15, now: now), now)              // shortened: overdue
        XCTAssertEqual(AutoCleaner.nextCheck(last: now.addingTimeInterval(3600), minutes: 60, now: now), now)  // clock went back
        XCTAssertEqual(AutoCleanView.interval(15), "15 min")
        XCTAssertEqual(AutoCleanView.interval(360), "6 hours")
        XCTAssertEqual(AutoCleanView.interval(1440), "Once a day")
        XCTAssertEqual(AutoCleanView.ago(now.addingTimeInterval(-40), now: now), "just now")
        XCTAssertEqual(AutoCleanView.ago(now.addingTimeInterval(-12 * 60 - 59), now: now), "12 min ago")
        XCTAssertEqual(AutoCleanView.ago(now.addingTimeInterval(-3 * 3600), now: now), "3 hr ago")
        XCTAssertEqual(AutoCleanView.ago(now.addingTimeInterval(-86_400), now: now), "1 day ago")
    }

    /// The schedule only checks when due, and remembers the last check across relaunches.
    @MainActor func testTickRespectsScheduleAndPersists() async throws {
        let suite = "ydnt-test-\(UUID())"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let defaults = UserDefaults(suiteName: suite)!
        let file = FileManager.default.temporaryDirectory.appending(path: "ydnt-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let c = AutoCleaner(history: History(file: file), defaults: defaults, poll: false)
        c.settings.thresholdPercent = 1          // never low on a test machine: checks are no-ops
        c.settings.stopPercent = 2
        XCTAssertNil(c.lastCheck)
        await c.tickOnce()                        // first ever: due
        let first = try XCTUnwrap(c.lastCheck)
        await c.tickOnce()                        // within the hour: not due
        XCTAssertEqual(c.lastCheck, first)
        XCTAssertEqual(c.nextCheck.timeIntervalSince(first), 3600, accuracy: 1)
        let again = AutoCleaner(history: History(file: file), defaults: defaults, poll: false)
        XCTAssertEqual(try XCTUnwrap(again.lastCheck).timeIntervalSince1970, first.timeIntervalSince1970, accuracy: 0.001)
    }

    func testOldSettingsDecodeWithDefaults() throws {
        let old = #"{"enabled":false,"thresholdPercent":20,"folders":[{"path":"/w"}]}"#
        let s = try JSONDecoder().decode(AutoCleanSettings.self, from: Data(old.utf8))
        XCTAssertFalse(s.enabled)
        XCTAssertEqual(s.thresholdPercent, 20)
        XCTAssertEqual(s.stopPercent, 25)
        XCTAssertFalse(s.askFirst)
        XCTAssertEqual(s.checkMinutes, 60)
        XCTAssertEqual(s.folders, [WatchedFolder(path: "/w", enabled: true)])
    }

    /// Dragging sliders must never delete: changes settle into one plan-only check.
    @MainActor func testSettingsChangeRePlansButNeverDeletes() async throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appending(path: "ydnt-\(UUID())")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        let file = dir.appending(path: "old.bin")
        try Data(count: 4096).write(to: file)
        try fm.setAttributes([.modificationDate: Date.now.addingTimeInterval(-30 * 86_400)], ofItemAtPath: file.path)

        let suite = "ydnt-test-\(UUID())"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let history = History(file: dir.appending(path: "history.json"))
        let c = AutoCleaner(history: history, defaults: UserDefaults(suiteName: suite)!, poll: false)
        c.settings.folders = [WatchedFolder(path: dir.path(percentEncoded: false))]
        c.settings.thresholdPercent = 99    // always "low"
        c.settings.stopPercent = 100
        XCTAssertTrue(c.rechecking)
        XCTAssertEqual(c.checkedSettings.thresholdPercent, 10)   // text keeps the last result until the new one lands

        try await Task.sleep(for: .seconds(1.8))
        XCTAssertFalse(c.rechecking)
        XCTAssertEqual(c.checkedSettings.thresholdPercent, 99)
        guard case .waiting(_, _, 1) = c.state else { return XCTFail("expected a 1-item plan, got \(c.state)") }
        XCTAssertTrue(fm.fileExists(atPath: file.path))
        XCTAssertTrue(history.entries.isEmpty)
    }
}
