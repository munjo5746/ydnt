import SwiftUI

/// One wedge of the donut + one legend row. Same shape at both levels.
struct Slice: Identifiable, Hashable {
    let id: String
    let name: String
    let path: String
    let bytes: Int64
    let color: Color
    let status: CategoryResult.Status

    static let shades: [Double] = [1, 0.8, 0.64, 0.5, 0.4, 0.32, 0.25]

    static func categories(_ results: [Category: CategoryResult]) -> [Slice] {
        Category.allCases.map { c in
            let r = results[c]
            return Slice(id: c.rawValue, name: c.name, path: c.displayPath, bytes: r?.bytes ?? 0,
                         color: c.color, status: r?.status ?? .scanning)
        }
        .sorted { $0.bytes > $1.bytes }
    }

    static func items(_ result: CategoryResult) -> [Slice] {
        result.items.enumerated().map { i, item in
            Slice(id: item.id, name: item.name, path: item.url.abbreviatedPath, bytes: item.bytes,
                  color: result.category.color.opacity(shades[i % shades.count]), status: .scanned)
        }
    }

    /// Maps a Swift Charts angle-selection value (cumulative bytes) back to a slice.
    static func at(angle: Double, in slices: [Slice]) -> Slice? {
        var acc = 0.0
        for s in slices where s.bytes > 0 {
            acc += Double(s.bytes)
            if angle <= acc { return s }
        }
        return nil
    }
}
