import SwiftUI

struct HistoryView: View {
    @Environment(AutoCleaner.self) private var cleaner

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("History").font(.system(size: 34, weight: .bold)).tracking(-1)
                Text("Everything deleted, by you or by auto-clean. Newest first.")
                    .font(.system(size: 12)).foregroundStyle(Theme.secondary)
            }
            .padding(EdgeInsets(top: 28, leading: 36, bottom: 24, trailing: 36))

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if cleaner.history.entries.isEmpty {
                        Text("Nothing deleted yet.").font(.system(size: 13)).foregroundStyle(Theme.secondary).padding(.vertical, 20)
                    }
                    ForEach(cleaner.history.runs) { run in
                        Text("\(run.date.formatted(date: .abbreviated, time: .shortened)) · \(run.auto ? "Auto" : "Manual") · freed \(Theme.bytes(run.freed)) · \(run.entries.count) item\(run.entries.count == 1 ? "" : "s")"
                             + (run.failed > 0 ? " · \(run.failed) failed" : ""))
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.secondary)
                            .padding(EdgeInsets(top: 18, leading: 10, bottom: 6, trailing: 10))
                        ForEach(run.entries) { e in row(e) }
                    }
                }
            }
            .overlay(alignment: .top) { Theme.divider.frame(height: 1) }
            .padding(EdgeInsets(top: 0, leading: 36, bottom: 32, trailing: 36))
        }
    }

    private func row(_ e: HistoryEntry) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(e.name).font(.system(size: 15, weight: .medium)).foregroundStyle(e.error == nil ? Theme.text : .red)
                Text(e.error ?? (e.path as NSString).abbreviatingWithTildeInPath)
                    .font(.system(size: 11)).monospaced().foregroundStyle(e.error == nil ? Theme.tertiary : .red)
            }
            Spacer(minLength: 8)
            Text(e.source).font(.system(size: 12)).foregroundStyle(Theme.secondary)
            Text(Theme.bytes(e.bytes)).font(.system(size: 15, weight: .semibold)).monospaced()
                .frame(minWidth: 90, alignment: .trailing)
            Button { reveal(e) } label: { Image(systemName: "folder") }
                .buttonStyle(.borderless).help("Show the folder it was in")
        }
        .lineLimit(1).truncationMode(.middle)
        .padding(.horizontal, 10).frame(minHeight: 52)
        .overlay(alignment: .bottom) { Theme.divider.frame(height: 1) }
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
