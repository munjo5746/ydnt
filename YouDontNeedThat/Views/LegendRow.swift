import SwiftUI

struct LegendRow: View {
    let slice: Slice
    let percent: String
    let active: Bool
    let queued: Bool
    var opens = false                   // row tap goes into a folder: show a chevron
    var onSelect: (() -> Void)? = nil   // nil: nothing to select (category rows, protected folders)
    let onHover: (Bool) -> Void
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 10) {
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
                    if opens { Image(systemName: "chevron.right").foregroundStyle(Theme.tertiary) }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if let onSelect {
                Button(action: onSelect) {
                    Image(systemName: queued ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(queued ? Theme.accent : Theme.tertiary).font(.system(size: 16))
                }
                .buttonStyle(.plain)
                .help(queued ? "Remove from the delete list" : "Add to the delete list")
            } else if queued {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent).font(.system(size: 16))
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 10)
        .frame(minHeight: 56)
        .background(active || queued ? Theme.rowActive : .clear)
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
