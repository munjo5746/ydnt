import SwiftUI

struct RootView: View {
    @Environment(AutoCleaner.self) private var cleaner
    @Environment(ScanModel.self) private var model
    @State private var open: Category?
    @State private var path: [URL] = []                      // folders opened inside `open`, outermost first
    @State private var folders: [URL: CategoryResult] = [:]  // contents of opened folders
    @State private var basket: [ScanItem: Category] = [:]   // picked for clean-up, across all categories
    @State private var errorMessage: String?
    @State private var screen = Screen.clean
    @State private var deleting = false
    @State private var reviewing = false
    @State private var trashMode = true
    @State private var confirmEmpty = false
    @State private var toast: Toast?

    struct Toast: Equatable {
        var text: String
        var undoRun: UUID? = nil
        var rescan: Set<Category> = []
        var canEmpty = false
    }

    /// One tile + one row: a category at the top level, an item inside one.
    private struct Entry: Identifiable {
        let id: String
        let name: String
        let path: String
        let bytes: Int64
        let color: Color
        let shade: Double       // 0 = full category color
        let modified: Date?
        var meta = ""
        var tag: String? = nil
        let isFolder: Bool
        let selectable: Bool
        var category: Category? = nil
        var item: ScanItem? = nil
    }

    private var openResult: CategoryResult? { path.last.map { folders[$0] } ?? open.flatMap { model.results[$0] } }
    private var basketBytes: Int64 { basket.keys.reduce(0) { $0 + $1.bytes } }
    private var basketPlaces: [String] {
        basket.sorted { $0.key.bytes > $1.key.bytes }.map(\.value.name).reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    }

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(screen: screen, go: go, emptyTrash: { confirmEmpty = true })
            Group {
                switch screen {
                case .clean: cleanScreen
                case .autoClean: AutoCleanView()
                case .history(let run): HistoryView(expand: run)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea(edges: .top)
        .overlay(alignment: .bottom) { toastView }
        .sheet(isPresented: $reviewing) {
            ConfirmSheet(items: basket.keys.sorted { $0.bytes > $1.bytes }, places: basketPlaces, free: cleaner.disk?.available,
                         trash: $trashMode, keep: { basket[$0] = nil }, cancel: { reviewing = false }, confirm: clean)
        }
        .onChange(of: basket.isEmpty) { _, empty in if empty { reviewing = false } }
        .onChange(of: cleaner.autoRuns) { model.scanAll(); folders = [:]; path.forEach(load) }
        .onChange(of: cleaner.pendingScreen, initial: true) { _, s in
            guard let s else { return }
            screen = s
            cleaner.pendingScreen = nil
        }
        .onAppear { NSApp.setActivationPolicy(.regular) }       // Dock icon only while the window is open
        .onDisappear { NSApp.setActivationPolicy(.accessory) }
        .confirmationDialog("Empty the Trash?", isPresented: $confirmEmpty, titleVisibility: .visible) {
            Button("Empty Trash", role: .destructive) { emptyTrash() }
        } message: { Text("Everything in the Trash is deleted for good. There is no undo.") }
        .background(Theme.window)
        .foregroundStyle(Theme.text)
        .font(.system(size: 13))
        .preferredColorScheme(.dark)
        .frame(minWidth: 1000, minHeight: 700)
        .task { if model.results.isEmpty { model.scanAll() } }
        .onExitCommand { goBack() }
        .alert("That didn't work", isPresented: Binding(get: { errorMessage != nil }, set: { _ in errorMessage = nil })) {
            Button("OK") {}
        } message: { Text(errorMessage ?? "") }
    }

    // MARK: Clean up

    private var cleanScreen: some View {
        VStack(spacing: 0) {
            cleanHeader
            StableScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    titleRow
                    level
                        .id("\(open?.rawValue ?? "")/\(path.last?.path ?? "")")
                        .transition(.scale(scale: 0.96, anchor: .top).combined(with: .opacity))
                }
                .padding(EdgeInsets(top: 24, leading: 28, bottom: 16, trailing: 28))
            }
            basketBar
        }
    }

    private var cleanHeader: some View {
        let crumbs = ["All places"] + (open.map { [$0.name] } ?? []) + path.map(\.lastPathComponent)
        return HStack(spacing: 8) {
            if open != nil {
                Button { goBack() } label: { Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold)) }
                    .buttonStyle(OutlineButtonStyle()).keyboardShortcut("[", modifiers: .command)
                    .accessibilityLabel("Back").disabled(deleting)
            }
            HStack(spacing: 2) {
                ForEach(crumbs.indices, id: \.self) { i in
                    if i > 0 { Text("›").foregroundStyle(Color(hex: 0x6E7178)).padding(.horizontal, 2) }
                    if i == crumbs.count - 1 {
                        Text(crumbs[i]).fontWeight(.semibold).padding(.horizontal, 8)
                    } else {
                        Button(crumbs[i]) { back(to: i) }.buttonStyle(GhostButtonStyle(tint: Theme.secondary, size: 30))
                            .padding(.horizontal, 2).disabled(deleting)
                    }
                }
            }
            .lineLimit(1)
            Spacer(minLength: 20)
            if model.isScanning {
                ProgressView().controlSize(.small)
                Text("Judging your files…").font(.system(size: 12)).foregroundStyle(Theme.tertiary)
            } else if let at = model.scannedAt {
                Text("Scanned \(Text(at, style: .relative)) ago").font(.system(size: 12)).foregroundStyle(Theme.tertiary)
            }
            Button { model.scanAll(); folders = [:]; path.forEach(load) } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
            }
            .buttonStyle(OutlineButtonStyle()).disabled(deleting || model.isScanning)
        }
        .padding(.horizontal, 24).frame(minHeight: 54)
        .overlay(alignment: .bottom) { Theme.divider.frame(height: 1) }
    }

    private var titleRow: some View {
        let (title, sub, big, caption): (String, String, Int64, String)
        if let here = path.last {
            let r = folders[here]
            title = here.lastPathComponent; sub = here.abbreviatedPath
            big = r?.bytes ?? 0; caption = itemsCaption(r?.items ?? [])
        } else if let c = open {
            let r = model.results[c]
            title = c.name; sub = c.displayPath
            big = r?.bytes ?? 0; caption = itemsCaption(r?.items ?? [])
        } else {
            let places = Category.allCases.filter { !pickable($0).isEmpty }.count
            title = "Where your space went"
            sub = "Biggest first. Click a tile or row to look inside, tick what you don't need."
            big = model.reclaimable; caption = "you could get back from \(Theme.plural(places, "place"))"
        }
        return HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 28, weight: .bold)).tracking(-0.5)
                Text(sub).foregroundStyle(Theme.secondary).truncationMode(.middle)
            }
            .lineLimit(1)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Theme.bytes(big)).font(Theme.mono(28)).foregroundStyle(Theme.accent)
                Text(caption).font(.system(size: 12)).foregroundStyle(Theme.tertiary)
            }
        }
    }

    private func itemsCaption(_ items: [ScanItem]) -> String {
        let prot = items.filter(\.isProtected).count
        return Theme.plural(items.count, "item") + (prot > 0 ? " · \(prot) protected by macOS" : "")
    }

    @ViewBuilder private var level: some View {
        let entries = self.entries
        VStack(alignment: .leading, spacing: 18) {
            if !entries.isEmpty {
                TreemapView(tiles: entries.map { e in
                    let check = check(e)
                    return TreemapTile(id: e.id, name: e.name, size: Theme.bytes(e.bytes), bytes: e.bytes, color: e.color,
                                       darkInk: e.shade <= 0.3, selected: check == .on, locked: !e.selectable,
                                       label: "\(e.name), \(Theme.bytes(e.bytes)). \(e.isFolder ? "Open" : e.selectable ? "Select" : "Protected")",
                                       action: { tapped(e) })
                })
                .frame(height: 230)
            }

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Text("Name").padding(.leading, 44).frame(maxWidth: .infinity, alignment: .leading)
                    Text("Last used").frame(width: 120, alignment: .leading)
                    Text("Size").frame(width: 170, alignment: .trailing)
                    Spacer().frame(width: 34)
                }
                .font(.system(size: 11, weight: .semibold)).tracking(0.5).textCase(.uppercase).foregroundStyle(Theme.tertiary)
                .frame(minHeight: 32)
                .overlay(alignment: .bottom) { Theme.track.frame(height: 1) }

                let top = entries.first?.bytes ?? 1
                ForEach(entries) { e in
                    let check = check(e)
                    ItemRow(name: e.name, path: e.path, bytes: e.bytes, barFraction: Double(e.bytes) / Double(max(top, 1)),
                            color: e.color, modified: e.modified, meta: e.meta, tag: e.tag, isFolder: e.isFolder,
                            check: check, selectable: e.selectable,
                            checkLocked: e.item.map { inherited($0.url) } ?? false || deleting,
                            onCheck: { toggle(e) }, onOpen: { tapped(e) })
                }
                levelFooter
            }
        }
    }

    /// Full Disk Access prompts, still-scanning and already-clean categories (top level), or this folder's state.
    @ViewBuilder private var levelFooter: some View {
        if open == nil {
            ForEach(Category.allCases.filter { model.results[$0]?.status == .needsAccess }) { c in
                HStack(spacing: 0) {
                    Image(systemName: "lock").foregroundStyle(Color(hex: 0xE8B45A)).frame(width: 44)
                        .accessibilityLabel("Needs access")
                    VStack(alignment: .leading, spacing: 3) {
                        Text(c.name).font(.system(size: 14, weight: .medium))
                        Text("macOS needs your OK before we can look inside \(Text(c.displayPath).font(Theme.mono(11, .regular)))")
                            .font(.system(size: 12)).foregroundStyle(Theme.tertiary)
                    }
                    Spacer()
                    Button("Grant Full Disk Access…") { ScanModel.openFullDiskAccessSettings() }
                        .buttonStyle(OutlineButtonStyle(tint: Theme.amber, stroke: Color(hex: 0x5C4A26))).padding(.trailing, 8)
                }
                .frame(minHeight: 56)
                .overlay(alignment: .bottom) { Theme.rowDivider.frame(height: 1) }
            }
            let scanning = Category.allCases.filter { model.results[$0]?.status == .scanning }
            if !scanning.isEmpty {
                note("Still judging: " + scanning.map(\.name).joined(separator: ", "), spinner: true)
            }
            let empties = Category.allCases.filter { model.results[$0].map { $0.status == .scanned && $0.bytes == 0 } ?? false }
            if !empties.isEmpty {
                note("Already clean: " + empties.map(\.name).joined(separator: ", "), spinner: false)
            }
        } else if let r = openResult {
            switch r.status {
            case .scanning: note("Judging your files…", spinner: true)
            case .needsAccess: note("macOS needs Full Disk Access before we can look inside.", spinner: false)
            case .scanned: if r.items.isEmpty { note("Nothing in here.", spinner: false) }
            }
        }
    }

    private func note(_ text: String, spinner: Bool) -> some View {
        HStack(spacing: 10) {
            if spinner { ProgressView().controlSize(.small) } else { Image(systemName: "checkmark") }
            Text(text)
        }
        .font(.system(size: 12)).foregroundStyle(Theme.tertiary)
        .padding(.leading, 14).frame(minHeight: 48)
    }

    private var basketBar: some View {
        HStack(spacing: 12) {
            if basket.isEmpty {
                Text("Tick what you don't need. Your picks stay here while you browse other folders.").foregroundStyle(Theme.secondary)
            } else {
                Text("\(basket.count)").fontWeight(.bold).foregroundStyle(Theme.ink)
                    .padding(.horizontal, 6).frame(minWidth: 28, minHeight: 28).background(Theme.accent, in: Capsule())
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(Theme.plural(basket.count, "item")) · \(Theme.bytes(basketBytes))").fontWeight(.semibold)
                    Text("From " + basketPlaces.joined(separator: ", ")).font(.system(size: 12)).foregroundStyle(Theme.tertiary)
                }
                .lineLimit(1)
            }
            Spacer(minLength: 20)
            if deleting {
                ProgressView().controlSize(.small)
                Text("Cleaning \(Theme.plural(basket.count, "item"))… big folders take a while.").foregroundStyle(Theme.secondary)
            } else if !basket.isEmpty {
                Button("Clear") { basket = [:] }.buttonStyle(OutlineButtonStyle(height: 36))
            }
            Button("Review & clean…") { reviewing = true }
                .buttonStyle(AccentButtonStyle()).disabled(basket.isEmpty || deleting)
        }
        .padding(.horizontal, 28).padding(.vertical, 14)
        .background(Theme.bar)
        .overlay(alignment: .top) { Theme.divider.frame(height: 1) }
    }

    @ViewBuilder private var toastView: some View {
        if let t = toast {
            HStack(spacing: 12) {
                Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.accent)
                Text(t.text).lineLimit(2)
                if let run = t.undoRun {
                    Button("Undo") { undo(run, t.rescan) }.buttonStyle(OutlineButtonStyle(stroke: Color(hex: 0x4A4D55), height: 30))
                }
                if t.canEmpty, (model.results[.trash]?.bytes ?? 0) > 0 {
                    Button("Empty Trash") { confirmEmpty = true }.buttonStyle(OutlineButtonStyle(stroke: Color(hex: 0x4A4D55), height: 30))
                }
                Button { toast = nil } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                    .buttonStyle(GhostButtonStyle(size: 30)).accessibilityLabel("Dismiss")
            }
            .padding(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 8))
            .background(Theme.track, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: 0x3C3F46)))
            .shadow(color: .black.opacity(0.5), radius: 15, y: 12)
            .padding(.leading, 220)       // centered on the content, not the sidebar
            .padding(.bottom, 84)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .accessibilityAddTraits(.updatesFrequently)
        }
    }

    // MARK: Entries and picking

    private var entries: [Entry] {
        if let c = open {
            return (openResult?.items ?? []).filter { $0.bytes > 0 }.enumerated().map { i, item in
                let shade = min(0.62, Double(i) * 0.15)
                return Entry(id: item.id, name: item.name, path: item.url.abbreviatedPath, bytes: item.bytes,
                             color: c.color.opacity(1 - shade), shade: shade, modified: item.modified,
                             meta: "", tag: item.isProtected ? "Protected by macOS" : nil,
                             isFolder: item.isDirectory, selectable: !item.isProtected, item: item)
            }
        }
        return Category.allCases.compactMap { c -> Entry? in
            guard let r = model.results[c], r.status == .scanned, r.bytes > 0 else { return nil }
            let prot = r.items.filter(\.isProtected).count
            return Entry(id: c.rawValue, name: c.name, path: c.displayPath, bytes: r.bytes, color: c.color, shade: 0,
                         modified: r.items.compactMap(\.modified).max(), meta: Theme.plural(r.items.count, "item"),
                         tag: prot > 0 ? "\(prot) protected" : nil, isFolder: true, selectable: prot < r.items.count,
                         category: c)
        }
        .sorted { $0.bytes > $1.bytes }
    }

    private func pickable(_ c: Category) -> [ScanItem] {
        model.results[c].map { $0.status == .scanned ? $0.items.filter { !$0.isProtected } : [] } ?? []
    }

    /// On because a folder above it is picked.
    private func inherited(_ url: URL) -> Bool { basket.keys.contains { url.isInside($0.url) } }

    private func check(_ url: URL) -> Check {
        if basket.keys.contains(where: { $0.url == url }) || inherited(url) { return .on }
        return basket.keys.contains { $0.url.isInside(url) } ? .mixed : .off
    }

    private func check(_ e: Entry) -> Check {
        if let item = e.item { return check(item.url) }
        guard let c = e.category else { return .off }
        let states = pickable(c).map { check($0.url) }
        if !states.isEmpty, states.allSatisfy({ $0 == .on }) { return .on }
        return states.contains { $0 != .off } ? .mixed : .off
    }

    /// Picks `item`, replacing anything already picked inside it.
    private func pick(_ item: ScanItem, _ c: Category) {
        for k in basket.keys where k.url.isInside(item.url) { basket[k] = nil }
        basket[item] = c
    }

    private func toggle(_ e: Entry) {
        guard !deleting else { return }
        if let item = e.item, let c = open {
            guard !item.isProtected, !inherited(item.url) else { return }
            if basket[item] != nil { basket[item] = nil } else { pick(item, c) }
        } else if let c = e.category {
            let items = pickable(c)
            if check(e) == .on {
                for k in basket.keys where items.contains(where: { k.url == $0.url || k.url.isInside($0.url) }) { basket[k] = nil }
            } else {
                for i in items where check(i.url) != .on { pick(i, c) }
            }
        }
    }

    private func tapped(_ e: Entry) {
        if let c = e.category {
            withAnimation(.easeOut(duration: 0.3)) { open = c }
        } else if let item = e.item {
            if item.isDirectory {
                withAnimation(.easeOut(duration: 0.3)) { path.append(item.url) }
                if folders[item.url] == nil { load(item.url) }
            } else if item.isProtected {
                toast = Toast(text: "\(item.name) is protected by macOS, so it's always skipped.")
            } else {
                toggle(e)
            }
        }
    }

    // MARK: Navigation

    private func go(_ s: Screen) {
        toast = nil
        withAnimation(.easeInOut(duration: 0.2)) { screen = s }
    }

    private func back(to crumb: Int) {
        guard !deleting else { return }
        withAnimation(.easeOut(duration: 0.3)) {
            if crumb == 0 { open = nil; path = []; folders = [:] } else { path = Array(path.prefix(crumb - 1)) }
        }
    }

    private func goBack() {
        guard !deleting, screen == .clean, open != nil else { return }
        back(to: path.count)
    }

    private func load(_ url: URL) {
        guard let c = open else { return }
        folders[url] = CategoryResult(category: c, status: .scanning, items: [])
        Task { folders[url] = await Task.detached { DiskScanner.contents(of: url, in: c) }.value }
    }

    // MARK: Actions

    private func rescan(_ cats: Set<Category>) {
        cats.forEach(model.rescan)
        folders = [:]
        path.forEach(load)
    }

    private func clean() {
        let batch = basket, trash = trashMode
        reviewing = false
        deleting = true
        toast = nil
        Task {
            let entries = await cleaner.delete(batch.map { Pick(item: $0.key, source: $0.value.name) }, auto: false, trash: trash)
            let failed = entries.filter { $0.error != nil }
            let failedPaths = Set(failed.map(\.path))
            let done = batch.filter { !failedPaths.contains($0.key.id) }
            for item in done.keys { basket[item] = nil }
            let touched = Set(done.values).union(trash ? [.trash] : [])
            rescan(touched)
            deleting = false
            let bytes = Theme.bytes(done.keys.reduce(0) { $0 + $1.bytes })
            if !done.isEmpty {
                withAnimation {
                    toast = trash
                        ? Toast(text: "Moved \(Theme.plural(done.count, "item")) to the Trash. Empty it to get \(bytes) back.",
                                undoRun: entries.first?.run, rescan: touched, canEmpty: true)
                        : Toast(text: "Deleted \(Theme.plural(done.count, "item")). \(bytes) is yours again.")
                }
            }
            if !failed.isEmpty {
                errorMessage = failed.map { "\($0.name): \($0.error ?? "")" }.sorted().joined(separator: "\n")
            }
        }
    }

    private func undo(_ run: UUID, _ cats: Set<Category>) {
        Task {
            let n = await cleaner.undoTrash(run: run)
            rescan(cats)
            toast = Toast(text: "Put back \(Theme.plural(n, "item")).")
        }
    }

    private func emptyTrash() {
        let bytes = model.results[.trash]?.bytes ?? 0
        Task {
            await cleaner.emptyTrash()
            rescan([.trash])
            toast = Toast(text: "Trash emptied. \(Theme.bytes(bytes)) is free space again.")
        }
    }
}

extension URL {
    /// Strictly below `other` in the folder tree.
    func isInside(_ other: URL) -> Bool {
        let a = standardizedFileURL.pathComponents, b = other.standardizedFileURL.pathComponents
        return a.count > b.count && a.starts(with: b)
    }
}
