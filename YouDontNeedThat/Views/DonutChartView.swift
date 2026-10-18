import SwiftUI
import Charts

struct DonutChartView<Center: View>: View {
    let slices: [Slice]
    let focused: String?            // hovered ?? picked
    @Binding var hovered: String?
    let onTap: (String) -> Void
    @ViewBuilder let center: Center
    @State private var angle: Double?

    var body: some View {
        Chart(slices.filter { $0.bytes > 0 }) { s in
            let active = s.id == focused
            SectorMark(angle: .value("Size", Double(s.bytes)),
                       innerRadius: .ratio(0.6),
                       outerRadius: .ratio(active ? 1 : 0.94),
                       angularInset: 1)
                .foregroundStyle(s.color)
                .opacity(focused == nil || active ? 1 : 0.45)
        }
        .chartLegend(.hidden)
        .chartAngleSelection(value: $angle)
        .onChange(of: angle) { _, a in hovered = a.flatMap { Slice.at(angle: $0, in: slices) }?.id }
        .onTapGesture { if let h = hovered { onTap(h) } }  // hover always precedes click on macOS
        .animation(.easeOut(duration: 0.2), value: focused)
        .overlay { center.padding(70).allowsHitTesting(false) }
    }
}
