import SwiftUI

enum Treemap {
    /// One rect per value (pass them largest first). Splits the list where its weight halves,
    /// cutting the longer side, and recurses into both halves.
    static func layout(_ values: [Double], in rect: CGRect) -> [CGRect] {
        var out = Array(repeating: CGRect.zero, count: values.count)
        func split(_ idx: ArraySlice<Int>, _ r: CGRect) {
            guard let first = idx.first else { return }
            guard idx.count > 1 else { out[first] = r; return }
            let total = idx.reduce(0) { $0 + values[$1] }
            var acc = values[first], k = idx.startIndex + 1
            while k < idx.endIndex - 1, acc + values[idx[k]] <= total / 2 { acc += values[idx[k]]; k += 1 }
            let f = total > 0 ? acc / total : 0.5
            let (a, b) = r.width >= r.height
                ? r.divided(atDistance: r.width * f, from: .minXEdge)
                : r.divided(atDistance: r.height * f, from: .minYEdge)
            split(idx[..<k], a)
            split(idx[k...], b)
        }
        split(ArraySlice(values.indices), rect)
        return out
    }
}

struct TreemapTile: Identifiable {
    let id: String
    let name: String
    let size: String
    let bytes: Int64
    let color: Color
    let darkInk: Bool       // text color on the tile
    let selected: Bool
    let locked: Bool        // nothing in it can be picked
    let label: String       // VoiceOver
    let action: () -> Void
}

struct TreemapView: View {
    let tiles: [TreemapTile]   // largest first

    var body: some View {
        GeometryReader { g in
            let rects = Treemap.layout(tiles.map { Double($0.bytes) }, in: CGRect(origin: .zero, size: g.size))
            ZStack(alignment: .topLeading) {
                ForEach(Array(zip(tiles, rects)), id: \.0.id) { t, r in
                    tile(t, r)
                }
            }
        }
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func tile(_ t: TreemapTile, _ r: CGRect) -> some View {
        let big = r.width > 70 && r.height > 46
        let fill = t.locked ? Theme.track : t.color
        let ink = t.locked || !t.darkInk ? Color(hex: 0xF4F5F7) : Color(hex: 0x0E0F11)
        return Button(action: t.action) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 9).fill(Theme.window)
                RoundedRectangle(cornerRadius: 9).fill(fill)
                if t.locked { Hatch().clipShape(RoundedRectangle(cornerRadius: 9)) }
                if big {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        Text(t.size).font(Theme.mono(12, .regular)).opacity(0.85)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                } else if r.width > 30, r.height > 22 {
                    Text(t.size).font(Theme.mono(11, .regular)).lineLimit(1).padding(6)
                }
            }
            .foregroundStyle(ink)
            .overlay {
                if t.selected { RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.accent, lineWidth: 3) }
            }
            .overlay(alignment: .topTrailing) {
                if t.selected {
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .black)).foregroundStyle(Theme.ink)
                        .frame(width: 20, height: 20).background(Theme.accent, in: Circle())
                        .overlay(Circle().stroke(Theme.window, lineWidth: 2)).padding(8)
                }
            }
            .padding(1)
            .brightness(hovered == t.id ? 0.06 : 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 ? t.id : (hovered == t.id ? nil : hovered) }
        .frame(width: r.width, height: r.height)
        .offset(x: r.minX, y: r.minY)
        .accessibilityLabel(t.label)
    }

    @State private var hovered: String?
}

/// Diagonal stripes on protected tiles.
private struct Hatch: View {
    var body: some View {
        Canvas { ctx, size in
            var p = Path()
            var x = -size.height
            while x < size.width {
                p.move(to: CGPoint(x: x, y: size.height)); p.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += 12
            }
            ctx.stroke(p, with: .color(.white.opacity(0.06)), lineWidth: 6)
        }
    }
}
