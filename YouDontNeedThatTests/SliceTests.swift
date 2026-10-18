import XCTest
@testable import YouDontNeedThat

final class SliceTests: XCTestCase {
    private func slice(_ id: String, _ bytes: Int64) -> Slice {
        Slice(id: id, name: id, path: id, bytes: bytes, color: .red, status: .scanned)
    }

    func testAngleMapsToSlice() {
        let s = [slice("a", 10), slice("empty", 0), slice("b", 30)]
        XCTAssertEqual(Slice.at(angle: 0, in: s)?.id, "a")
        XCTAssertEqual(Slice.at(angle: 10, in: s)?.id, "a")
        XCTAssertEqual(Slice.at(angle: 10.1, in: s)?.id, "b")
        XCTAssertEqual(Slice.at(angle: 40, in: s)?.id, "b")
        XCTAssertNil(Slice.at(angle: 41, in: s))
    }

    @MainActor func testCategorySlicesSortedLargestFirst() {
        let results = Dictionary(uniqueKeysWithValues: Fixtures.fake.map { ($0.category, $0) })
        let bytes = Slice.categories(results).map(\.bytes)
        XCTAssertEqual(bytes, bytes.sorted(by: >))
        XCTAssertEqual(bytes.first, 43_700_000_000)
    }

    func testItemSlicesCycleShades() {
        let r = Fixtures.fake.first { $0.category == .caches }!
        let slices = Slice.items(r)
        XCTAssertEqual(slices.count, 7)
        XCTAssertEqual(slices.map(\.bytes), r.items.map(\.bytes))
    }
}
