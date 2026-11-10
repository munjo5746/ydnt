import SwiftUI

struct AutoCleanView: View {
    @Environment(AutoCleaner.self) private var cleaner
    @State private var refused: [String] = []

    var body: some View {
        @Bindable var cleaner = cleaner
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Auto-clean").font(.system(size: 34, weight: .bold)).tracking(-1)
                Text("When free space drops below the threshold, the oldest items in these folders are permanently deleted, skipping the Trash, until it's back above.")
                    .font(.system(size: 12)).foregroundStyle(Theme.secondary)
            }
            .padding(EdgeInsets(top: 28, leading: 36, bottom: 24, trailing: 36))

            VStack(alignment: .leading, spacing: 16) {
                Toggle("Auto-clean on", isOn: $cleaner.settings.enabled)
                Toggle("Open at login (menu bar only)", isOn: Binding(get: { cleaner.launchAtLogin }, set: { cleaner.launchAtLogin = $0 }))
                Stepper("Clean when free space is below \(cleaner.settings.thresholdPercent)%",
                        value: $cleaner.settings.thresholdPercent, in: 1...50)
                if let d = cleaner.disk { FreeSpaceBar(disk: d, threshold: cleaner.settings.thresholdPercent).frame(maxWidth: 420) }
            }
            .font(.system(size: 14))
            .padding(.horizontal, 36)

            HStack {
                Text("WATCHED FOLDERS").font(.system(size: 12)).tracking(1).foregroundStyle(Theme.secondary)
                Spacer()
                Button("Add folder…") { addFolders() }.buttonStyle(OutlineButtonStyle()).controlSize(.small)
            }
            .padding(EdgeInsets(top: 28, leading: 36, bottom: 12, trailing: 36))

            ScrollView {
                LazyVStack(spacing: 0) {
                    if cleaner.settings.folders.isEmpty {
                        Text("No folders yet. Nothing will be deleted until you add one.")
                            .font(.system(size: 13)).foregroundStyle(Theme.secondary).padding(.vertical, 20)
                    }
                    ForEach($cleaner.settings.folders) { $f in
                        HStack(spacing: 14) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(f.name).font(.system(size: 15, weight: .medium))
                                Text(f.url.abbreviatedPath).font(.system(size: 11)).monospaced().foregroundStyle(Theme.tertiary)
                            }
                            Spacer(minLength: 8)
                            Stepper(f.minAgeDays == 0 ? "Anything" : "Older than \(f.minAgeDays) day\(f.minAgeDays == 1 ? "" : "s")",
                                    value: $f.minAgeDays, in: 0...365)
                                .font(.system(size: 13)).monospacedDigit()
                            Button { cleaner.settings.folders.removeAll { $0.id == f.id } } label: { Image(systemName: "xmark") }
                                .buttonStyle(.borderless).help("Stop watching this folder")
                        }
                        .lineLimit(1).truncationMode(.middle)
                        .padding(.horizontal, 10).frame(minHeight: 56)
                        .overlay(alignment: .bottom) { Theme.divider.frame(height: 1) }
                    }
                }
            }
            .overlay(alignment: .top) { Theme.divider.frame(height: 1) }
            .padding(EdgeInsets(top: 0, leading: 36, bottom: 32, trailing: 36))
        }
        .alert("Can't watch that", isPresented: Binding(get: { !refused.isEmpty }, set: { _ in refused = [] })) {
            Button("OK") {}
        } message: {
            Text("\(refused.joined(separator: "\n"))\n\nSystem folders, your home folder and its top-level Library, Documents and Desktop are off limits.")
        }
    }

    private func addFolders() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Watch"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard AutoCleaner.isAllowed(url) else { refused.append(url.abbreviatedPath); continue }
            let path = url.standardizedFileURL.path(percentEncoded: false)
            if !cleaner.settings.folders.contains(where: { $0.path == path }) {
                cleaner.settings.folders.append(WatchedFolder(path: path, minAgeDays: 30))
            }
        }
    }
}
