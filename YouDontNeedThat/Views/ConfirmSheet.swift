import SwiftUI

/// "Get rid of N items?": the picks, Trash vs delete, confirm.
struct ConfirmSheet: View {
    let items: [ScanItem]
    let places: [String]
    let free: Int64?
    @Binding var trash: Bool
    let keep: (ScanItem) -> Void
    let cancel: () -> Void
    let confirm: () -> Void

    private var bytes: Int64 { items.reduce(0) { $0 + $1.bytes } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Get rid of \(Theme.plural(items.count, "item"))?").font(.system(size: 20, weight: .bold))
                Text("\(Theme.bytes(bytes)) from \(places.joined(separator: ", ")). Protected items are never included.")
                    .foregroundStyle(Theme.secondary)
            }
            .padding(EdgeInsets(top: 22, leading: 24, bottom: 14, trailing: 24))

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(items) { item in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name).fontWeight(.medium)
                                Text(item.url.abbreviatedPath).font(Theme.mono(11, .regular)).foregroundStyle(Theme.tertiary)
                            }
                            .truncationMode(.middle)
                            Spacer(minLength: 8)
                            Text(Theme.bytes(item.bytes)).font(Theme.mono(13))
                            Button { keep(item) } label: { Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)) }
                                .buttonStyle(GhostButtonStyle()).help("Keep this").accessibilityLabel("Keep \(item.name)")
                        }
                        .lineLimit(1)
                        .frame(minHeight: 48)
                        .overlay(alignment: .bottom) { Theme.divider.frame(height: 1) }
                    }
                }
                .padding(EdgeInsets(top: 0, leading: 24, bottom: 0, trailing: 12))
            }
            .frame(maxHeight: 220)
            .overlay(alignment: .top) { Theme.track.frame(height: 1) }
            .overlay(alignment: .bottom) { Theme.track.frame(height: 1) }

            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("How should they go?")
                HStack(spacing: 10) {
                    option("Move to Trash", "You can undo. Space comes back when you empty the Trash.", on: trash, danger: false) { trash = true }
                    option("Delete now", "Space comes back right away. This can't be undone.", on: !trash, danger: true) { trash = false }
                }
                Text(trash ? "They go to the Trash. Empty it later to actually get \(Theme.bytes(bytes)) back."
                     : free.map { "Free space goes from \(Theme.bytes($0)) to \(Theme.bytes($0 + bytes)) the moment you click." }
                        ?? "Space comes back the moment you click.")
                    .foregroundStyle(Color(hex: 0xDADBDF)).fixedSize(horizontal: false, vertical: true)
            }
            .padding(EdgeInsets(top: 16, leading: 24, bottom: 16, trailing: 24))

            HStack(spacing: 10) {
                Spacer()
                Button("Cancel", action: cancel).buttonStyle(OutlineButtonStyle(height: 36)).keyboardShortcut(.cancelAction)
                Button(trash ? "Move to Trash" : "Delete \(Theme.bytes(bytes)) for good", action: confirm)
                    .buttonStyle(AccentButtonStyle(fill: trash ? Theme.accent : Theme.danger, ink: trash ? Theme.ink : .white))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(EdgeInsets(top: 14, leading: 24, bottom: 14, trailing: 24))
            .background(Color(hex: 0x18191C))
            .overlay(alignment: .top) { Theme.track.frame(height: 1) }
        }
        .font(.system(size: 13))
        .frame(width: 560)
        .background(Theme.raised)
        .foregroundStyle(Theme.text)
    }

    private func option(_ title: String, _ detail: String, on: Bool, danger: Bool, action: @escaping () -> Void) -> some View {
        let tint = danger ? Color(hex: 0xFF7A70) : Theme.accent
        return Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(Color(hex: 0xB6B8BE)).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(on ? tint.opacity(0.12) : Color(hex: 0x202226), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(on ? tint : Color(hex: 0x34373D), lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
