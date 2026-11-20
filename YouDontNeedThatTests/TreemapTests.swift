import XCTest
@testable import YouDontNeedThat

final class TreemapTests: XCTestCase {
    func testAreasMatchValuesAndTileTheRect() {
        let values: [Double] = [50, 25, 15, 10]
        let rect = CGRect(x: 0, y: 0, width: 400, height: 100)
        let rects = Treemap.layout(values, in: rect)
        XCTAssertEqual(rects.count, 4)
        for (v, r) in zip(values, rects) {
            XCTAssertEqual(r.width * r.height, v / 100 * 40_000, accuracy: 0.001)
            XCTAssertTrue(rect.contains(r))
        }
        for i in rects.indices { for j in rects.indices where i < j {
            XCTAssertEqual(rects[i].intersection(rects[j]).width * rects[i].intersection(rects[j]).height, 0, accuracy: 0.001)
        } }
        XCTAssertEqual(rects[0], CGRect(x: 0, y: 0, width: 200, height: 100))   // biggest half, cut along the long side
    }

    func testEdgeCases() {
        XCTAssertTrue(Treemap.layout([], in: .init(x: 0, y: 0, width: 10, height: 10)).isEmpty)
        XCTAssertEqual(Treemap.layout([5], in: .init(x: 0, y: 0, width: 10, height: 10)), [.init(x: 0, y: 0, width: 10, height: 10)])
        XCTAssertEqual(Treemap.layout([0, 0], in: .init(x: 0, y: 0, width: 10, height: 10)).map(\.width), [5, 5])
    }

    func testIsInside() {
        let a = URL(fileURLWithPath: "/a/b"), b = URL(fileURLWithPath: "/a/b/c")
        XCTAssertTrue(b.isInside(a))
        XCTAssertFalse(a.isInside(a))
        XCTAssertFalse(a.isInside(b))
        XCTAssertFalse(URL(fileURLWithPath: "/a/bc").isInside(a))
    }
}
