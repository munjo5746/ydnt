import SwiftUI

struct RootView: View {
    @Environment(AutoCleaner.self) private var cleaner
    @State private var model = ScanModel()
    @State private var open: Category?
    @State private var path: [URL] = []                      // folders opened inside `open`, outermost first
    @State private var folders: [URL: CategoryResult] = [:]  // contents of opened folders
    @State private var hovered: String?
    @State private var basket: [ScanItem: Category] = [:]   // queued for deletion, across all categories
    @State private var errorMessage: String?
    @State private var screen = Screen.chart
    @State private var deleting = false
    @State private var confirmDelete = false

    private var openResult: CategoryResult? { path.last.map { folders[$0] } ?? open.flatMap { model.results[$0] } }
    private var here: (name: String, path: String)? {
        path.last.map { ($0.lastPathComponent, $0.abbreviatedPath) } ?? open.map { ($0.name, $0.displayPath) }
    }
    private var scanning: Bool { path.isEmpty ? model.isScanning : openResult?.status != .scanned }
    private var slices: [Slice] { openResult.map(Slice.items) ?? Slice.categories(model.results) }
    private var total: Int64 { slices.reduce(0) { $0 + $1.bytes } }
    private var focused: Slice? { slices.first { $0.id == hovered } }
    private var basketBytes: Int64 { basket.keys.reduce(0) { $0 + $1.bytes } }
    private func queued(_ id: String) -> Bool { basket.keys.contains { $0.id == id } }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Group {
                switch screen {
                case .chart: level.id(open)
                case .deleteList: deleteList
                case .autoClean: AutoCleanView()
                case .history(let run): HistoryView(runID: run) { go(.history(run: $0)) }
                }
            }
            .transition(.opacity)
            footer
        }
        .onChange(of: basket.isEmpty) { _, empty in if empty, screen == .deleteList { screen = .chart } }
        .onChange(of: cleaner.autoRuns) { model.scanAll(); folders = [:]; path.last.map(load) }
        .onChange(of: cleaner.pendingScreen, initial: true) { _, s in
            guard let s else { return }
            screen = s
            cleaner.pendingScreen = nil
        }
        .onAppear { NSApp.setActivationPolicy(.regular) }       // Dock icon only while the window is open
        .onDisappear { NSApp.setActivationPolicy(.accessory) }
        .confirmationDialog("Permanently delete \(basket.count) file\(basket.count == 1 ? "" : "s") (\(Theme.bytes(basketBytes)))?",
                            isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { deleteAll() }
        } message: { Text("This skips the Trash. There is no undo.") }
        .background(Theme.window)
        .foregroundStyle(Theme.text)
        .preferredColorScheme(.dark)
        .frame(minWidth: 980, minHeight: 680)
        .task { model.scanAll() }
        .onExitCommand { goBack() }
        .alert("That didn't work", isPresented: Binding(get: { errorMessage != nil }, set: { _ in errorMessage = nil })) {
            Button("OK") {}
        } message: { Text(errorMessage ?? "") }
    }

    // MARK: Sections

    private var titleBar: some View {
        HStack(spacing: 16) {
            Text("You Don't Need That").font(.system(size: 14, weight: .bold))
            Spacer()
            HStack(spacing: 8) {
                if !crumbs.isEmpty {
                    Button { goBack() } label: { Label("Back", systemImage: "chevron.left") }
                        .buttonStyle(OutlineButtonStyle())
                        .keyboardShortcut("[", modifiers: .command)
                        .controlSize(.small)
                        .disabled(deleting)
                    Text("All places").foregroundStyle(Theme.secondary)
                    ForEach(crumbs.indices, id: \.self) { i in
                        Text("/").foregroundStyle(Theme.secondary)
                        Text(crumbs[i]).fontWeight(i == crumbs.count - 1 ? .medium : .regular)
                            .foregroundStyle(i == crumbs.count - 1 ? Theme.text : Theme.secondary)
                    }
                } else {
                    Text("All places").fontWeight(.medium)
                }
            }
            .font(.system(size: 13))
            if screen == .chart {
                HStack(spacing: 8) {
                    Button("Auto-clean") { go(.autoClean) }
                    Button("History") { go(.history(run: nil)) }
                }
                .buttonStyle(OutlineButtonStyle()).controlSize(.small).disabled(deleting)
            }
        }
        .padding(.leading, 84)
        .padding(.trailing, 20)
        .frame(height: 52)
        .background(Theme.titleBar)
        .overlay(alignment: .bottom) { Theme.divider.frame(height: 1) }
    }

    private var level: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(here.map { scanning ? $0.name : "\($0.name): \(Theme.bytes(total))" } ?? "Where your space went")
                        .font(.system(size: 34, weight: .bold)).tracking(-1)
                    Text(here?.path ?? "Your home folder, scanned for clutter")
                        .font(.system(size: 12)).monospaced().foregroundStyle(Theme.secondary)
                }
                Spacer()
                HStack(spacing: 10) {
                    if scanning {
                        ProgressView().controlSize(.small)
                        Text(openResult?.status == .needsAccess ? "Needs Full Disk Access" : "Judging your files…")
                    } else {
                        Text(open == nil ? "Click a slice to look inside." : "Click a folder to open it, ○ to select.")
                        if open == nil {
                            Button("Rescan") { model.scanAll() }.buttonStyle(OutlineButtonStyle()).controlSize(.small)
                        }
                    }
                }
                .font(.system(size: 13)).foregroundStyle(Theme.secondary)
            }
            .padding(EdgeInsets(top: 28, leading: 36, bottom: 0, trailing: 36))

            HStack(alignment: .top, spacing: 32) {
                DonutChartView(slices: slices, focused: focused?.id, hovered: $hovered, onTap: tapped) { centerLabel }
                    .frame(width: 400, height: 400)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(slices) { s in
                            let item = item(s.id)
                            LegendRow(slice: s, percent: percent(s.bytes), active: s.id == focused?.id,
                                      queued: open != nil && queued(s.id), opens: item?.isDirectory == true,
                                      onSelect: item.flatMap { i in i.isProtected ? nil : { toggle(i) } },
                                      onHover: { hovered = $0 ? s.id : nil }, onTap: { tapped(s.id) })
                        }
                    }
                }
                .overlay(alignment: .top) { Theme.divider.frame(height: 1) }
            }
            .padding(EdgeInsets(top: 24, leading: 36, bottom: 32, trailing: 36))
        }
    }

    private var centerLabel: some View {
        let (kicker, size, name, path): (String, String, String, String) = if let f = focused {
            ("\(percent(f.bytes)) of \(here?.name ?? "total")", Theme.bytes(f.bytes), f.name, f.path)
        } else if let h = here {
            ("This directory", Theme.bytes(total), h.name, h.path)
        } else {
            ("Reclaimable", Theme.bytes(total), "\(slices.filter { $0.bytes > 0 }.count) places", "~")
        }
        return VStack(spacing: 4) {
            Text(kicker.uppercased()).font(.system(size: 12)).tracking(1).foregroundStyle(Theme.secondary)
            Text(size).font(.system(size: 30, weight: .semibold)).monospaced().foregroundStyle(Theme.accent)
            Text(name).font(.system(size: 15, weight: .medium))
            Text(path).font(.system(size: 10)).monospaced().foregroundStyle(Theme.tertiary).truncationMode(.middle)
        }
        .lineLimit(1)
        .multilineTextAlignment(.center)
    }

    private var footer: some View {
        FooterBar(note: footerNote) {
            if open == nil, model.needsAccess {
                Button("Grant Full Disk Access") { ScanModel.openFullDiskAccessSettings() }.buttonStyle(OutlineButtonStyle())
            }
            switch screen {
            case .deleteList:
                if deleting { ProgressView().controlSize(.small) }
                Button(deleting ? "Deleting…" : "Delete \(basket.count) file\(basket.count == 1 ? "" : "s")") { confirmDelete = true }
                    .buttonStyle(AccentButtonStyle()).disabled(deleting)
            case .autoClean:
                Button("Run now") { Task { await cleaner.check(force: true) } }.buttonStyle(OutlineButtonStyle())
            case .history(let run):
                if run == nil, !cleaner.history.entries.isEmpty {
                    Button("Clear history") { cleaner.history.clear() }.buttonStyle(OutlineButtonStyle())
                }
            case .chart:
                if !basket.isEmpty {
                    Button("Review delete list (\(basket.count))") { go(.deleteList) }.buttonStyle(AccentButtonStyle())
                }
            }
        }
    }

    private var deleteList: some View {
        let items = basket.keys.sorted { $0.bytes > $1.bytes }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Delete list: \(Theme.bytes(basketBytes))").font(.system(size: 34, weight: .bold)).tracking(-1)
                    Text("Nothing is deleted until you confirm. Remove anything you want to keep.")
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }
                Spacer()
                HStack(spacing: 10) {
                    Button("Show in Finder") { reveal() }.buttonStyle(OutlineButtonStyle())
                    Button("Clear all") { basket = [:] }.buttonStyle(OutlineButtonStyle())
                }
                .controlSize(.small).disabled(deleting)
            }
            .padding(EdgeInsets(top: 28, leading: 36, bottom: 24, trailing: 36))

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(items) { item in
                        HStack(spacing: 14) {
                            RoundedRectangle(cornerRadius: 3).fill(basket[item]?.color ?? Theme.secondary).frame(width: 12, height: 12)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.name).font(.system(size: 15, weight: .medium))
                                Text(item.url.abbreviatedPath).font(.system(size: 11)).monospaced().foregroundStyle(Theme.tertiary)
                            }
                            Spacer(minLength: 8)
                            Text(basket[item]?.name ?? "").font(.system(size: 12)).foregroundStyle(Theme.secondary)
                            Text(Theme.bytes(item.bytes)).font(.system(size: 15, weight: .semibold)).monospaced()
                                .frame(minWidth: 90, alignment: .trailing)
                            Button("Keep") { basket[item] = nil }.buttonStyle(OutlineButtonStyle()).controlSize(.small)
                                .disabled(deleting).help("Remove from the delete list")
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
    }

    /// Breadcrumb after "All places".
    private var crumbs: [String] {
        switch screen {
        case .chart: open.map { [$0.name] + path.map(\.lastPathComponent) } ?? []
        case .deleteList: ["Delete list"]
        case .autoClean: ["Auto-clean"]
        case .history(nil): ["History"]
        case .history(let id?):
            ["History", cleaner.history.runs.first { $0.id == id }?.date.formatted(date: .abbreviated, time: .shortened) ?? "Run"]
        }
    }

    private var footerNote: String {
        if screen == .autoClean { return cleaner.state.detail }
        if screen == .history(run: nil) {
            let n = cleaner.history.runs.count
            return "\(n) run\(n == 1 ? "" : "s") logged"
        }
        if case .history = screen { return "Deleted files skipped the Trash and can't be restored." }
        if deleting { return "Deleting \(basket.count) item\(basket.count == 1 ? "" : "s")… big folders take a while." }
        if !basket.isEmpty { return "\(basket.count) item\(basket.count == 1 ? "" : "s") · \(Theme.bytes(basketBytes)) on the delete list" }
        if open == nil { return "Nothing is deleted until you say so." }
        return "Nothing queued. Pick the slices you don't need."
    }

    // MARK: Actions

    private func percent(_ b: Int64) -> String {
        guard total > 0 else { return "" }
        let pct = Double(b) / Double(total) * 100
        return pct < 1 ? "<1%" : "\(Int(pct.rounded()))%"
    }

    private func item(_ id: String) -> ScanItem? {
        open == nil ? nil : openResult?.items.first { $0.id == id }
    }

    private func toggle(_ item: ScanItem) {
        guard let c = open, !item.isProtected else { return }
        if basket.removeValue(forKey: item) == nil { basket[item] = c }
    }

    private func tapped(_ id: String) {
        if open != nil {
            guard let item = item(id) else { return }
            if item.isDirectory {
                withAnimation(.easeInOut(duration: 0.25)) { path.append(item.url); hovered = nil }
                if folders[item.url] == nil { load(item.url) }
            } else {
                toggle(item)
            }
        } else if let c = Category(rawValue: id) {
            if model.results[c]?.status == .needsAccess { ScanModel.openFullDiskAccessSettings(); return }
            withAnimation(.easeInOut(duration: 0.25)) { open = c; hovered = nil }
        }
    }

    private func goBack() {
        guard !deleting else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            if case .history(_?) = screen { screen = .history(run: nil) } else if screen != .chart { screen = .chart }
            else if !path.isEmpty { path.removeLast() } else { open = nil; folders = [:] }
            hovered = nil
        }
    }

    private func load(_ url: URL) {
        guard let c = open else { return }
        folders[url] = CategoryResult(category: c, status: .scanning, items: [])
        Task { folders[url] = await Task.detached { DiskScanner.contents(of: url, in: c) }.value }
    }

    private func go(_ s: Screen) {
        withAnimation(.easeInOut(duration: 0.25)) { screen = s; hovered = nil }
    }

    private func reveal() {
        NSWorkspace.shared.activateFileViewerSelecting(basket.keys.map(\.url))
    }

    private func deleteAll() {
        let batch = basket
        deleting = true
        Task {
            let entries = await cleaner.delete(batch.map { Pick(item: $0.key, source: $0.value.name) }, auto: false)
            let failed = entries.filter { $0.error != nil }
            let failedPaths = Set(failed.map(\.path))
            let done = batch.filter { !failedPaths.contains($0.key.url.path(percentEncoded: false)) }
            for item in done.keys { basket[item] = nil }
            Set(done.values).forEach(model.rescan)
            folders = [:]
            path.forEach(load)
            deleting = false
            if !failed.isEmpty {
                errorMessage = failed.map { "\($0.name): \($0.error ?? "")" }.sorted().joined(separator: "\n")
            }
        }
    }
}
