import SwiftUI

/// Runs list, or one run's detail when `runID` is set.
struct HistoryView: View {
    @Environment(AutoCleaner.self) private var cleaner
    let runID: UUID?
    let onSelect: (UUID) -> Void

    var body: some View {
        if let runID, let run = cleaner.history.runs.first(where: { $0.id == runID }) {
            detail(run)
        } else {
            list
        }
    }

    // MARK: List

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            header("History", "Every delete, by you or by auto-clean. Newest first.")
            ScrollView {
                LazyVStack(spacing: 0) {
                    if cleaner.history.entries.isEmpty {
                        Text("Nothing deleted yet.").font(.system(size: 13)).foregroundStyle(Theme.secondary).padding(.vertical, 20)
                    }
                    ForEach(cleaner.history.runs) { run in
                        Button { onSelect(run.id) } label: { runRow(run) }.buttonStyle(.plain)
                    }
                }
            }
            .overlay(alignment: .top) { Theme.divider.frame(height: 1) }
            .padding(EdgeInsets(top: 0, leading: 36, bottom: 32, trailing: 36))
        }
    }

    private func runRow(_ run: History.Run) -> some View {
        HStack(spacing: 14) {
            Text(run.date.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 15, weight: .medium))
                .frame(minWidth: 170, alignment: .leading)
            Text(run.auto ? "AUTO" : "MANUAL").font(.system(size: 10, weight: .bold)).tracking(1)
                .foregroundStyle(run.auto ? Theme.accent : Theme.secondary)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(run.auto ? Theme.accent : Theme.border))
            Spacer(minLength: 8)
            Text("\(run.entries.count) item\(run.entries.count == 1 ? "" : "s")").font(.system(size: 12)).foregroundStyle(Theme.secondary)
            if run.failed > 0 {
                Text("\(run.failed) failed").font(.system(size: 12)).foregroundStyle(.red)
            }
            Text(Theme.bytes(run.freed)).font(.system(size: 15, weight: .semibold)).monospaced()
                .frame(minWidth: 90, alignment: .trailing)
            Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(Theme.secondary)
        }
        .lineLimit(1)
        .padding(.horizontal, 10).frame(minHeight: 56)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { Theme.divider.frame(height: 1) }
    }

    // MARK: Detail

    private func detail(_ run: History.Run) -> some View {
        var sub = "\(run.auto ? "Auto-clean" : "Manual delete") · \(run.date.formatted(date: .long, time: .shortened))"
        if let b = run.freeBefore, let a = run.freeAfter { sub += " · \(CleanState.pct(b)) → \(CleanState.pct(a)) free" }
        return VStack(alignment: .leading, spacing: 0) {
            header("Freed \(Theme.bytes(run.freed))", sub)
            HStack(spacing: 28) {
                stat("\(run.succeeded.count)", "deleted", Theme.accent)
                stat("\(run.failed)", "failed", run.failed > 0 ? .red : Theme.secondary)
                stat("\(run.entries.count)", "total", Theme.text)
            }
            .padding(EdgeInsets(top: 0, leading: 36, bottom: 20, trailing: 36))

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !run.failures.isEmpty {
                        section("Failed (\(run.failed))")
                        ForEach(run.failures) { row($0) }
                    }
                    section("Deleted (\(run.succeeded.count))")
                    ForEach(run.succeeded.sorted { $0.bytes > $1.bytes }) { row($0) }
                }
            }
            .overlay(alignment: .top) { Theme.divider.frame(height: 1) }
            .padding(EdgeInsets(top: 0, leading: 36, bottom: 32, trailing: 36))
        }
    }

    private func stat(_ value: String, _ label: String, _ color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(value).font(.system(size: 22, weight: .semibold)).monospaced().foregroundStyle(color)
            Text(label).font(.system(size: 13)).foregroundStyle(Theme.secondary)
        }
    }

    private func section(_ title: String) -> some View {
        Text(title.uppercased()).font(.system(size: 12, weight: .semibold)).tracking(1).foregroundStyle(Theme.secondary)
            .padding(EdgeInsets(top: 18, leading: 10, bottom: 6, trailing: 10))
    }

    private func row(_ e: HistoryEntry) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(e.name).font(.system(size: 15, weight: .medium)).foregroundStyle(e.error == nil ? Theme.text : .red)
                Text((e.path as NSString).abbreviatingWithTildeInPath)
                    .font(.system(size: 11)).monospaced().foregroundStyle(Theme.tertiary)
                if let error = e.error {
                    Text(error).font(.system(size: 11)).foregroundStyle(.red)
                }
            }
            Spacer(minLength: 8)
            Text(e.source).font(.system(size: 12)).foregroundStyle(Theme.secondary)
            Text(Theme.bytes(e.bytes)).font(.system(size: 15, weight: .semibold)).monospaced()
                .frame(minWidth: 90, alignment: .trailing)
            Button { reveal(e) } label: { Image(systemName: "folder") }
                .buttonStyle(.borderless).help(e.error == nil ? "Show the folder it was in" : "Show in Finder")
        }
        .lineLimit(1).truncationMode(.middle)
        .padding(.horizontal, 10).frame(minHeight: 52)
        .overlay(alignment: .bottom) { Theme.divider.frame(height: 1) }
    }

    private func header(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 34, weight: .bold)).tracking(-1)
            Text(subtitle).font(.system(size: 12)).foregroundStyle(Theme.secondary)
        }
        .padding(EdgeInsets(top: 28, leading: 36, bottom: 20, trailing: 36))
    }

    private func reveal(_ e: HistoryEntry) {
        let file = URL(fileURLWithPath: e.path)
        // Failed deletes are still there; deleted ones aren't, so open the folder they were in.
        if FileManager.default.fileExists(atPath: e.path) {
            NSWorkspace.shared.activateFileViewerSelecting([file])
        } else {
            NSWorkspace.shared.open(file.deletingLastPathComponent())
        }
    }
}
