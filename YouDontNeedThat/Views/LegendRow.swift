import SwiftUI

struct LegendRow: View {
    let slice: Slice
    let percent: String
    let active: Bool
    let onHover: (Bool) -> Void
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 3).fill(slice.color).frame(width: 12, height: 12)
                VStack(alignment: .leading, spacing: 3) {
                    Text(slice.name).font(.system(size: 15, weight: .medium))
                    Text(slice.path).font(.system(size: 11)).monospaced()
                        .foregroundStyle(Theme.tertiary).truncationMode(.middle)
                }
                Spacer(minLength: 8)
                trailing
            }
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(minHeight: 56)
            .background(active ? Theme.rowActive : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover(perform: onHover)
        .overlay(alignment: .bottom) { Theme.divider.frame(height: 1) }
    }

    @ViewBuilder private var trailing: some View {
        switch slice.status {
        case .scanning:
            ProgressView().controlSize(.small)
        case .needsAccess:
            Text("Needs Full Disk Access").font(.system(size: 12)).foregroundStyle(Theme.secondary)
        case .scanned:
            VStack(alignment: .trailing, spacing: 2) {
                Text(Theme.bytes(slice.bytes)).font(.system(size: 15, weight: .semibold)).monospaced()
                Text(percent).font(.system(size: 12)).foregroundStyle(Theme.tertiary)
            }
        }
    }
}
