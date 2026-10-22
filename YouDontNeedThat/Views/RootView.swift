import SwiftUI

struct RootView: View {
    @State private var model = ScanModel()
    @State private var open: Category?
    @State private var hovered: String?
    @State private var basket: [ScanItem: Category] = [:]   // queued for deletion, across all categories
    @State private var errorMessage: String?
    @State private var reviewing = false      // showing the delete list instead of the chart
    @State private var deleting = false
    @State private var confirmDelete = false

    private var openResult: CategoryResult? { open.flatMap { model.results[$0] } }
    private var slices: [Slice] { openResult.map(Slice.items) ?? Slice.categories(model.results) }
    private var total: Int64 { slices.reduce(0) { $0 + $1.bytes } }
    private var focused: Slice? { slices.first { $0.id == hovered } }
    private var basketBytes: Int64 { basket.keys.reduce(0) { $0 + $1.bytes } }
    private func queued(_ id: String) -> Bool { basket.keys.contains { $0.id == id } }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Group {
                if reviewing { deleteList } else { level.id(open) }
            }
            .transition(.opacity)
            footer
        }
        .onChange(of: basket.isEmpty) { _, empty in if empty { reviewing = false } }
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
                if let here = reviewing ? "Delete list" : open?.name {
                    Button { goBack() } label: { Label("Back", systemImage: "chevron.left") }
                        .buttonStyle(OutlineButtonStyle())
                        .keyboardShortcut("[", modifiers: .command)
                        .controlSize(.small)
                        .disabled(deleting)
                    Text("All places").foregroundStyle(Theme.secondary)
                    Text("/").foregroundStyle(Theme.secondary)
                    Text(here).fontWeight(.medium)
                } else {
                    Text("All places").fontWeight(.medium)
                }
            }
            .font(.system(size: 13))
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
                    Text(open.map { "\($0.name): \(Theme.bytes(total))" } ?? "Where your space went")
                        .font(.system(size: 34, weight: .bold)).tracking(-1)
                    Text(open?.displayPath ?? "Your home folder, scanned for clutter")
                        .font(.system(size: 12)).monospaced().foregroundStyle(Theme.secondary)
                }
                Spacer()
                HStack(spacing: 10) {
                    if model.isScanning {
                        ProgressView().controlSize(.small)
                        Text("Judging your files…")
                    } else {
                        Text(open == nil ? "Click a slice to look inside." : "Click a slice to select it.")
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
                            LegendRow(slice: s, percent: percent(s.bytes), active: s.id == focused?.id,
                                      queued: open != nil && queued(s.id),
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
            ("\(percent(f.bytes)) of \(open?.name ?? "total")", Theme.bytes(f.bytes), f.name, f.path)
        } else if let c = open {
            ("This directory", Theme.bytes(total), c.name, c.displayPath)
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
            if reviewing {
                if deleting { ProgressView().controlSize(.small) }
                Button(deleting ? "Deleting…" : "Delete \(basket.count) file\(basket.count == 1 ? "" : "s")") { confirmDelete = true }
                    .buttonStyle(AccentButtonStyle()).disabled(deleting)
            } else if !basket.isEmpty {
                Button("Review delete list (\(basket.count))") { withAnimation(.easeInOut(duration: 0.25)) { reviewing = true; hovered = nil } }
                    .buttonStyle(AccentButtonStyle())
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

    private var footerNote: String {
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

    private func tapped(_ id: String) {
        if let c = open {
            guard let item = model.results[c]?.items.first(where: { $0.id == id }) else { return }
            if basket.removeValue(forKey: item) == nil { basket[item] = c }
        } else if let c = Category(rawValue: id) {
            if model.results[c]?.status == .needsAccess { ScanModel.openFullDiskAccessSettings(); return }
            withAnimation(.easeInOut(duration: 0.25)) { open = c; hovered = nil }
        }
    }

    private func goBack() {
        guard !deleting else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            if reviewing { reviewing = false } else { open = nil }
            hovered = nil
        }
    }

    private func reveal() {
        NSWorkspace.shared.activateFileViewerSelecting(basket.keys.map(\.url))
    }

    /// Deletes off the main thread: removing a folder like DerivedData touches every file inside it.
    private func deleteAll() {
        let batch = basket
        deleting = true
        Task {
            let failed = await Task.detached { () -> [ScanItem: String] in
                var failed: [ScanItem: String] = [:]
                for item in batch.keys {
                    do { try FileManager.default.removeItem(at: item.url) } catch { failed[item] = error.localizedDescription }
                }
                return failed
            }.value
            let done = batch.filter { failed[$0.key] == nil }
            for item in done.keys { basket[item] = nil }
            Set(done.values).forEach(model.rescan)
            deleting = false
            if !failed.isEmpty {
                errorMessage = failed.map { "\($0.key.name): \($0.value)" }.sorted().joined(separator: "\n")
            }
        }
    }
}
