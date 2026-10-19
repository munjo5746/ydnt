import SwiftUI

struct RootView: View {
    @State private var model = ScanModel()
    @State private var open: Category?
    @State private var hovered: String?
    @State private var basket: [ScanItem: Category] = [:]   // queued for deletion, across all categories
    @State private var errorMessage: String?
    @State private var showQueue = false
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
            ZStack(alignment: .bottom) {
                level.id(open).transition(.opacity)
                if showQueue, !basket.isEmpty { queuePanel }
            }
            footer
        }
        .animation(.easeInOut(duration: 0.2), value: showQueue)
        .animation(.easeInOut(duration: 0.2), value: basket.isEmpty)
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
                if let c = open {
                    Button { goBack() } label: { Label("Back", systemImage: "chevron.left") }
                        .buttonStyle(OutlineButtonStyle())
                        .keyboardShortcut("[", modifiers: .command)
                        .controlSize(.small)
                    Text("All places").foregroundStyle(Theme.secondary)
                    Text("/").foregroundStyle(Theme.secondary)
                    Text(c.name).fontWeight(.medium)
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
            if !basket.isEmpty {
                Button { showQueue.toggle() } label: {
                    Label(showQueue ? "Hide list" : "Review list", systemImage: showQueue ? "chevron.down" : "chevron.up")
                }
                .buttonStyle(OutlineButtonStyle())
                Button("Delete \(basket.count) file\(basket.count == 1 ? "" : "s")") { confirmDelete = true }.buttonStyle(AccentButtonStyle())
            }
        }
    }

    private var queuePanel: some View {
        let items = basket.keys.sorted { $0.bytes > $1.bytes }
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Queued for deletion").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Show in Finder") { reveal() }.buttonStyle(.plain).foregroundStyle(Theme.secondary)
                Button("Clear all") { basket = [:] }.buttonStyle(.plain).foregroundStyle(Theme.secondary)
                Button { showQueue = false } label: { Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)) }
                    .buttonStyle(.plain).foregroundStyle(Theme.secondary).padding(.leading, 8)
            }
            .font(.system(size: 13))
            .padding(.horizontal, 36).padding(.vertical, 12)
            Theme.divider.frame(height: 1)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(items) { item in
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 3).fill(basket[item]!.color).frame(width: 10, height: 10)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name).font(.system(size: 13, weight: .medium))
                                Text(item.url.abbreviatedPath).font(.system(size: 10)).monospaced().foregroundStyle(Theme.tertiary)
                            }
                            Spacer(minLength: 8)
                            Text(Theme.bytes(item.bytes)).font(.system(size: 13)).monospaced()
                            Button { basket[item] = nil } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.secondary)
                            }
                            .buttonStyle(.plain).help("Put back")
                        }
                        .lineLimit(1).truncationMode(.middle)
                        .padding(.horizontal, 36).frame(minHeight: 40)
                        .overlay(alignment: .bottom) { Theme.divider.frame(height: 1) }
                    }
                }
            }
            .frame(maxHeight: 280)
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(Theme.footer)
        .overlay(alignment: .top) { Theme.divider.frame(height: 1) }
        .shadow(color: .black.opacity(0.5), radius: 20, y: -4)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var footerNote: String {
        if !basket.isEmpty { return "\(basket.count) item\(basket.count == 1 ? "" : "s") · \(Theme.bytes(basketBytes)) queued" }
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
        withAnimation(.easeInOut(duration: 0.25)) { open = nil; hovered = nil }
    }

    private func reveal() {
        NSWorkspace.shared.activateFileViewerSelecting(basket.keys.map(\.url))
    }

    private func deleteAll() {
        var failed: [String] = []
        var touched = Set<Category>()
        for (item, c) in basket {
            do {
                try FileManager.default.removeItem(at: item.url)
                basket[item] = nil
                touched.insert(c)
            } catch {
                failed.append("\(item.name): \(error.localizedDescription)")
            }
        }
        touched.forEach(model.rescan)
        if !failed.isEmpty { errorMessage = failed.joined(separator: "\n") }
    }
}
