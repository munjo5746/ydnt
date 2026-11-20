import SwiftUI

struct Sidebar: View {
    @Environment(AutoCleaner.self) private var cleaner
    @Environment(ScanModel.self) private var scan
    let screen: Screen
    let go: (Screen) -> Void
    let emptyTrash: () -> Void

    private var isHistory: Bool { if case .history = screen { true } else { false } }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            BrandLockup().padding(EdgeInsets(top: 40, leading: 10, bottom: 0, trailing: 8))

            VStack(spacing: 2) {
                nav("Clean up", "square.grid.2x2", screen == .clean, .clean) {
                    Text(Theme.bytes(scan.reclaimable)).font(Theme.mono(11, .regular)).foregroundStyle(Theme.secondary)
                }
                nav("Auto-clean", "clock.badge.checkmark", screen == .autoClean, .autoClean) { autoBadge }
                nav("History", "clock.arrow.circlepath", isHistory, .history(run: nil)) {
                    Text("\(cleaner.history.runs.count)").font(Theme.mono(11, .regular)).foregroundStyle(Theme.secondary)
                }
            }

            Spacer()
            if let d = cleaner.disk { diskCard(d) }
        }
        .padding(EdgeInsets(top: 0, leading: 10, bottom: 14, trailing: 10))
        .frame(width: 220)
        .frame(maxHeight: .infinity)
        .background(Theme.sidebar)
        .overlay(alignment: .trailing) { Theme.divider.frame(width: 1) }
    }

    private func nav(_ title: String, _ icon: String, _ on: Bool, _ target: Screen,
                     @ViewBuilder trailing: () -> some View) -> some View {
        Button { go(target) } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).frame(width: 16)
                Text(title)
                Spacer()
                trailing()
            }
            .font(.system(size: 13, weight: on ? .semibold : .regular))
            .foregroundStyle(on ? .white : Theme.soft)
            .padding(.horizontal, 10).frame(minHeight: 36)
            .background(on ? Theme.active : .clear, in: RoundedRectangle(cornerRadius: 7))
            .hoverFill(Theme.raised)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var autoBadge: some View {
        let s = cleaner.settings.enabled
        let (label, fg, bg): (String, Color, Color) =
            !s ? ("Off", Theme.secondary, Theme.track)
            : cleaner.state.alert ? ("Low", Theme.amber, Color(hex: 0x3A2F17))
            : ("On", Theme.accent, Theme.accent.opacity(0.16))
        return Text(label).font(.system(size: 11, weight: .semibold)).foregroundStyle(fg)
            .padding(.horizontal, 7).padding(.vertical, 2).background(bg, in: Capsule())
    }

    private func diskCard(_ d: DiskSpace) -> some View {
        let trash = scan.results[.trash].flatMap { $0.status == .scanned ? $0.bytes : nil } ?? 0
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Macintosh HD").fontWeight(.semibold)
                Spacer()
                Text("\(CleanState.pct(d.free)) free").font(Theme.mono(11, .regular)).foregroundStyle(Theme.secondary)
            }
            SpaceBar(free: d.free, start: cleaner.settings.thresholdPercent, height: 8, parts: SpacePart.usage(scan, d))
            Text("\(Theme.bytes(d.available)) free of \(Theme.bytes(d.total))").font(.system(size: 12)).foregroundStyle(Theme.soft)
            if trash > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(Theme.bytes(trash)) is sitting in the Trash, still taking up space.")
                        .font(.system(size: 12)).foregroundStyle(Theme.soft).fixedSize(horizontal: false, vertical: true)
                    Button("Empty Trash", action: emptyTrash).buttonStyle(OutlineButtonStyle())
                }
                .padding(.top, 10)
                .overlay(alignment: .top) { Theme.divider.frame(height: 1) }
            }
        }
        .font(.system(size: 13))
        .padding(14)
        .background(Color(hex: 0x17181B), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.divider))
        .padding(.horizontal, 4)
    }
}
