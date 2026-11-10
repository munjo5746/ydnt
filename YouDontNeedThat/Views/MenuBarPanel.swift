import SwiftUI

/// What drops down from the menu bar icon.
struct MenuBarPanel: View {
    @Environment(AutoCleaner.self) private var cleaner
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: cleaner.state.symbol).foregroundStyle(Theme.accent)
                Text(cleaner.state.detail).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
            }

            if let d = cleaner.disk { FreeSpaceBar(disk: d, threshold: cleaner.settings.thresholdPercent) }

            if let run = cleaner.history.runs.first {
                VStack(alignment: .leading, spacing: 6) {
                    Text("LAST DELETE · \(run.auto ? "AUTO" : "MANUAL")").font(.system(size: 11)).tracking(1).foregroundStyle(Theme.secondary)
                    Text("\(run.date.formatted(.relative(presentation: .named))) · freed \(Theme.bytes(run.freed)) · \(run.entries.count) item\(run.entries.count == 1 ? "" : "s")"
                         + (run.failed > 0 ? " · \(run.failed) failed" : ""))
                        .font(.system(size: 12))
                    ForEach(cleaner.history.entries.prefix(5)) { e in
                        HStack {
                            Text(e.name).foregroundStyle(e.error == nil ? Theme.text : .red)
                            Spacer()
                            Text(Theme.bytes(e.bytes)).monospaced().foregroundStyle(Theme.secondary)
                        }
                        .font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                    }
                    Button("See all history") { open(.history) }.buttonStyle(.link).font(.system(size: 12))
                }
            }

            Theme.divider.frame(height: 1)
            HStack(spacing: 8) {
                Button("Run now") { Task { await cleaner.check(force: true) } }
                Button(cleaner.settings.enabled ? "Pause" : "Resume") { cleaner.settings.enabled.toggle() }
                Spacer()
                Button("Open") { open(nil) }
                Button("Quit") { NSApp.terminate(nil) }
            }
            .controlSize(.small)
        }
        .padding(16)
        .frame(width: 320)
        .background(Theme.window)
        .foregroundStyle(Theme.text)
        .preferredColorScheme(.dark)
        .onAppear { cleaner.refreshDisk() }
    }

    private func open(_ screen: Screen?) {
        cleaner.pendingScreen = screen
        openWindow(id: "main")
        NSApp.activate()
    }
}

struct FreeSpaceBar: View {
    let disk: DiskSpace
    let threshold: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.divider)
                    Capsule().fill(disk.free * 100 < Double(threshold) ? .orange : Theme.accent)
                        .frame(width: g.size.width * disk.free)
                    Rectangle().fill(Theme.text).frame(width: 2, height: 12)
                        .offset(x: g.size.width * Double(threshold) / 100 - 1)
                }
            }
            .frame(height: 8)
            Text("\(Theme.bytes(disk.available)) free of \(Theme.bytes(disk.total)) (\(CleanState.pct(disk.free))) · cleans below \(threshold)%")
                .font(.system(size: 11)).foregroundStyle(Theme.secondary)
        }
    }
}
