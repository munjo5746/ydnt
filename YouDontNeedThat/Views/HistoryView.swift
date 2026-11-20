import SwiftUI
import UniformTypeIdentifiers

/// Every clean-up as an expandable card. `expand` opens one run, e.g. from the menu bar.
struct HistoryView: View {
    @Environment(AutoCleaner.self) private var cleaner
    let expand: UUID?
    @State private var open: Set<UUID> = []
    @State private var filter = Filter.all
    @State private var confirmClear = false

    enum Filter: String, CaseIterable { case all = "All", you = "By you", auto = "Auto-clean", skipped = "With skipped items" }

    private var runs: [History.Run] {
        cleaner.history.runs.filter {
            switch filter {
            case .all: true
            case .you: !$0.auto
            case .auto: $0.auto
            case .skipped: $0.failed > 0
            }
        }
    }

    var body: some View {
        let all = cleaner.history.runs
        VStack(spacing: 0) {
            HStack { Text("History").fontWeight(.semibold); Spacer() }
                .padding(.horizontal, 28).frame(minHeight: 54)
                .overlay(alignment: .bottom) { Theme.divider.frame(height: 1) }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 10) {
                        stat("Cleaned in total", Theme.bytes(all.reduce(0) { $0 + $1.freed }), Theme.accent)
                        stat("Clean-ups", "\(all.count)", Theme.text)
                        stat("Items gone", "\(all.reduce(0) { $0 + $1.succeeded.count })", Theme.text)
                    }
                    HStack(spacing: 6) {
                        ForEach(Filter.allCases, id: \.self) { f in Chip(label: f.rawValue, on: filter == f) { filter = f } }
                    }
                    VStack(spacing: 10) {
                        ForEach(runs) { card($0) }
                        if runs.isEmpty {
                            Text("Nothing here yet. Go judge some files.").foregroundStyle(Theme.tertiary)
                                .frame(maxWidth: .infinity).padding(.vertical, 40)
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: 0x2E3035), style: StrokeStyle(lineWidth: 1, dash: [4])))
                        }
                    }
                }
                .padding(24).padding(.horizontal, 4)
                .pinnedScrollBar()
            }
            HStack(spacing: 12) {
                Text("History is kept for \(History.keepDays) days.").foregroundStyle(Theme.tertiary)
                Spacer()
                Button("Export CSV", action: export).buttonStyle(OutlineButtonStyle(height: 36)).disabled(all.isEmpty)
                Button("Clear history") { confirmClear = true }.buttonStyle(OutlineButtonStyle(height: 36)).disabled(all.isEmpty)
            }
            .padding(.horizontal, 28).padding(.vertical, 14)
            .background(Theme.bar)
            .overlay(alignment: .top) { Theme.divider.frame(height: 1) }
        }
        .onAppear { if let expand { open.insert(expand) } else if let first = all.first { open.insert(first.id) } }
        .onChange(of: expand) { _, id in if let id { open.insert(id) } }
        .confirmationDialog("Clear all history?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear history", role: .destructive) { cleaner.history.clear() }
        } message: { Text("Only the log goes. Nothing on disk changes.") }
    }

    private func stat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 12)).foregroundStyle(Theme.tertiary)
            Text(value).font(Theme.mono(24)).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
    }

    private func card(_ run: History.Run) -> some View {
        let isOpen = open.contains(run.id)
        return VStack(spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { if isOpen { open.remove(run.id) } else { open.insert(run.id) } }
            } label: {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(run.date.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 14, weight: .semibold))
                            Text(run.auto ? "Auto-clean" : "You").font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(run.auto ? Theme.accent : Color(hex: 0xD9DADD))
                                .padding(.horizontal, 8).padding(.vertical, 2)
                                .background(run.auto ? Theme.accent.opacity(0.16) : Theme.track, in: Capsule())
                        }
                        Text("\(Theme.plural(run.succeeded.count, "item")) · \(run.trashed ? "moved to the Trash" : "deleted for good")")
                            .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                    if run.failed > 0 {
                        Text("\(run.failed) skipped").font(.system(size: 11)).foregroundStyle(Theme.amber)
                            .padding(.horizontal, 8).padding(.vertical, 3).background(Color(hex: 0x2B2619), in: Capsule())
                    }
                    Text(Theme.bytes(run.freed)).font(Theme.mono(16))
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.secondary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                }
                .padding(.horizontal, 16).padding(.vertical, 10).frame(minHeight: 60)
                .hoverFill(Color(hex: 0x1E2024), radius: 0)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isOpen ? "expanded" : "collapsed")

            if isOpen {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(run.succeeded.sorted { $0.bytes > $1.bytes }) { row($0) }
                    if run.failed > 0 {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "info.circle").foregroundStyle(Theme.amber)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(Theme.plural(run.failed, "item")) skipped").fontWeight(.medium).foregroundStyle(Theme.amber)
                                Text(skippedText(run)).font(.system(size: 12)).foregroundStyle(Theme.soft)
                                    .fixedSize(horizontal: false, vertical: true).lineSpacing(2)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(hex: 0x211F19), in: RoundedRectangle(cornerRadius: 8))
                        .padding(.top, 12)
                    }
                }
                .padding(EdgeInsets(top: 4, leading: 16, bottom: 12, trailing: 16))
                .overlay(alignment: .top) { Theme.track.frame(height: 1) }
            }
        }
        .background(Color(hex: 0x191A1E), in: RoundedRectangle(cornerRadius: 10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.track))
    }

    private func skippedText(_ run: History.Run) -> String {
        let names = run.failures.map(\.name)
        let list = names.prefix(4).joined(separator: ", ") + (names.count > 4 ? " and \(names.count - 4) more" : "")
        return run.auto
            ? "\(list). macOS wouldn't let these go, so they were left alone. Auto-clean won't try them again."
            : "\(list). macOS wouldn't let these go, so they were left alone."
    }

    private func row(_ e: HistoryEntry) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(e.name)
                Text((e.path as NSString).abbreviatingWithTildeInPath).font(Theme.mono(11, .regular)).foregroundStyle(Theme.tertiary)
            }
            .truncationMode(.middle)
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(e.source).font(.system(size: 12)).foregroundStyle(Theme.secondary).frame(width: 110, alignment: .leading)
            Text(e.trashedTo == nil ? "Deleted" : "In Trash").font(.system(size: 12)).foregroundStyle(Theme.secondary)
                .frame(width: 80, alignment: .leading)
            Text(Theme.bytes(e.bytes)).font(Theme.mono(13)).frame(width: 90, alignment: .trailing)
            Button { reveal(e) } label: { Image(systemName: "folder").font(.system(size: 12)) }
                .buttonStyle(GhostButtonStyle()).help(e.trashedTo == nil ? "Show the folder it was in" : "Show in the Trash")
                .accessibilityLabel("Show in Finder")
        }
        .lineLimit(1)
        .frame(minHeight: 44)
        .overlay(alignment: .bottom) { Color(hex: 0x232529).frame(height: 1) }
    }

    private func reveal(_ e: HistoryEntry) {
        if let t = e.trashedTo, FileManager.default.fileExists(atPath: t) {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: t)])
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: e.path).deletingLastPathComponent())
        }
    }

    private func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "ydnt-history.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? cleaner.history.csv.write(to: url, atomically: true, encoding: .utf8)
    }
}
