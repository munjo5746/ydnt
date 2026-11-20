import SwiftUI

struct AutoCleanView: View {
    @Environment(AutoCleaner.self) private var cleaner
    @Environment(ScanModel.self) private var scan
    @State private var refused: [String] = []
    @State private var showPlan = false
    @State private var eligible: [String: (count: Int, bytes: Int64)] = [:]   // by folder path

    var body: some View {
        @Bindable var cleaner = cleaner
        VStack(spacing: 0) {
            HStack { Text("Auto-clean").fontWeight(.semibold); Spacer() }
                .padding(.horizontal, 28).frame(minHeight: 54)
                .overlay(alignment: .bottom) { Theme.divider.frame(height: 1) }
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    hero
                    whenToClean
                    foldersSection
                    neverTouched
                }
                .frame(maxWidth: 860, alignment: .leading)
                .padding(EdgeInsets(top: 24, leading: 28, bottom: 32, trailing: 28))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task(id: cleaner.settings.folders) { await measure() }
        .onChange(of: cleaner.autoRuns) { eligible = [:]; Task { await measure() } }
        .alert("Can't watch that", isPresented: Binding(get: { !refused.isEmpty }, set: { _ in refused = [] })) {
            Button("OK") {}
        } message: {
            Text("\(refused.joined(separator: "\n"))\n\nSystem folders, your home folder and its top-level Library, Documents and Desktop, iCloud Drive, cloud storage folders and photo libraries are off limits.")
        }
    }

    // MARK: Hero

    /// The longest helper text the card can show, with worst-case numbers.
    private static let longestDetail = "At the next check (within 10 minutes) it deletes 999 old items, freeing 999.99 GB. Or clean now."

    private var hero: some View {
        @Bindable var cleaner = cleaner
        // Headline and helper text follow the settings the current result was computed with, so they always agree.
        // The bar markers and legend follow the live sliders, for instant feedback while dragging.
        let s = cleaner.checkedSettings
        let live = cleaner.settings
        let free = cleaner.disk?.free ?? 1
        let busy = cleaner.rechecking
        let (kicker, color, headline, detail): (String, Color, String, String) = {
            if !s.enabled { return ("Off", Theme.secondary, "Auto-clean is off", "Nothing gets deleted unless you do it yourself.") }
            switch cleaner.state {
            case .waiting(_, let b, let n) where s.askFirst:
                return ("Waiting for your OK", Theme.amber, "You're under \(s.thresholdPercent)% free",
                        "It can free \(Theme.bytes(b)) by deleting \(Theme.plural(n, "old item")) and get you back toward \(s.stopPercent)%.")
            case .waiting(_, let b, let n):
                return ("Cleaning soon", Theme.amber, "You're under \(s.thresholdPercent)% free",
                        "At the next check (within 10 minutes) it deletes \(Theme.plural(n, "old item")), freeing \(Theme.bytes(b)). Or clean now.")
            case .stuck:
                return ("Stuck", Theme.amber, "You're under \(s.thresholdPercent)% free",
                        "Nothing in your folders is old enough to delete. Add folders below.")
            case .low, .planning, .deleting:
                return ("Cleaning", Theme.amber, "You're under \(s.thresholdPercent)% free", cleaner.state.detail)
            default:
                return ("Watching", Theme.accent, "All good: \(CleanState.pct(free)) free",
                        "Auto-clean steps in when free space drops below \(s.thresholdPercent)% and stops once it's back above \(s.stopPercent)%.")
            }
        }()
        let waiting: (bytes: Int64, count: Int)? = if case .waiting(_, let b, let n) = cleaner.state, s.enabled { (b, n) } else { nil }
        let working: Bool = switch cleaner.state { case .low, .planning, .deleting: true; default: false }

        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        if busy || working { ProgressView().controlSize(.mini) }
                        Text((busy ? "Checking with your new settings…" : kicker).uppercased())
                            .font(.system(size: 12, weight: .semibold)).tracking(0.7)
                            .foregroundStyle(busy ? Theme.secondary : color)
                    }
                    Group {
                        Text(headline).font(.system(size: 24, weight: .bold)).tracking(-0.4)
                        // Sized by the longest message at this width (hidden), so the card never jumps
                        // and there's no empty line when everything fits on one.
                        ZStack(alignment: .topLeading) {
                            Text(Self.longestDetail).hidden().accessibilityHidden(true)
                            Text(detail).foregroundStyle(Theme.soft)
                        }
                        .font(.system(size: 14))
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .opacity(busy ? 0.4 : 1)
                }
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.25), value: "\(busy)\(kicker)\(headline)\(detail)")
                .accessibilityElement(children: .combine)
                Spacer()
                Toggle("Auto-clean", isOn: $cleaner.settings.enabled).toggleStyle(.switch).labelsHidden().tint(Theme.accent)
            }
            if let d = cleaner.disk {
                let parts = SpacePart.usage(scan, d)
                VStack(alignment: .leading, spacing: 12) {
                    SpaceBar(free: d.free, start: live.thresholdPercent, stop: live.stopPercent, height: 14, parts: parts)
                        .padding(.top, -6)   // the pin heads already add room above
                    HStack(spacing: 18) {
                        Text("\(Theme.bytes(d.available)) free of \(Theme.bytes(d.total)) (\(CleanState.pct(d.free)))")
                        MarkerLegend(color: Theme.amber, text: "Starts below \(live.thresholdPercent)%")
                        MarkerLegend(color: Theme.text, text: "Stops at \(live.stopPercent)%")
                    }
                    .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    if !parts.isEmpty { SpaceLegend(parts: parts, free: d.available).padding(.top, 2) }
                }
                .animation(.easeOut(duration: 0.12), value: live)   // short: keeps up with a drag
            }
            // Always here, so nothing below jumps as the plan comes and goes; disabled when there's nothing to clean.
            HStack(spacing: 10) {
                Button(waiting.map { "Clean \(Theme.bytes($0.bytes)) now" } ?? "Clean now") { Task { await cleaner.check(force: true) } }
                    .buttonStyle(AccentButtonStyle(height: 38))
                    .disabled(waiting == nil)
                Button(showPlan ? "Hide list" : "See what would go") { showPlan.toggle() }
                    .buttonStyle(OutlineButtonStyle(height: 38))
            }
            .disabled(busy || working)   // the plan is about to change
            if showPlan {
                VStack(alignment: .leading, spacing: 0) {
                    SectionLabel("Oldest first. This is what would go.").padding(.top, 10).padding(.bottom, 4)
                    if waiting == nil {
                        Text("Nothing right now. Space is fine, or nothing in your folders is old enough.")
                            .foregroundStyle(Theme.tertiary).frame(minHeight: 36)
                    }
                    ForEach(waiting == nil ? [] : cleaner.pending, id: \.item.id) { p in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(p.item.name)
                                Text(p.item.url.abbreviatedPath).font(Theme.mono(11, .regular)).foregroundStyle(Theme.tertiary)
                            }
                            .truncationMode(.middle)
                            Spacer()
                            Text(p.source).font(.system(size: 12)).foregroundStyle(Theme.secondary).frame(width: 110, alignment: .leading)
                            Text(Theme.bytes(p.item.bytes)).font(Theme.mono(13)).frame(width: 80, alignment: .trailing)
                        }
                        .lineLimit(1).frame(minHeight: 36)
                        .overlay(alignment: .bottom) { Theme.divider.frame(height: 1) }
                    }
                }
                .overlay(alignment: .top) { Color(hex: 0x2E3035).frame(height: 1) }
            }
        }
        .padding(22)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(color == Theme.amber ? Color(hex: 0x5C4A26) : Color(hex: 0x2E3035)))
    }

    // MARK: Settings

    private var whenToClean: some View {
        @Bindable var cleaner = cleaner
        let total = cleaner.disk?.total ?? 0
        return VStack(alignment: .leading, spacing: 14) {
            Text("When to clean").font(.system(size: 15, weight: .semibold))
            slider("Start when free space drops below", value: Binding(
                get: { Double(cleaner.settings.thresholdPercent) },
                set: { v in
                    cleaner.settings.thresholdPercent = Int(v)
                    cleaner.settings.stopPercent = max(cleaner.settings.stopPercent, Int(v) + 1)
                }), range: 3...30, tint: Theme.amber, total: total)
            slider("Stop once it's back above", value: Binding(
                get: { Double(cleaner.settings.stopPercent) },
                set: { cleaner.settings.stopPercent = max(Int($0), cleaner.settings.thresholdPercent + 1) }),
                   range: 4...40, tint: Theme.text, total: total)
            HStack(spacing: 16) {
                Text("When it's time").foregroundStyle(Theme.soft).frame(width: 260, alignment: .leading)
                Chip(label: "Ask me first", on: cleaner.settings.askFirst) { cleaner.settings.askFirst = true }
                Chip(label: "Just do it", on: !cleaner.settings.askFirst) { cleaner.settings.askFirst = false }
            }
        }
    }

    private func slider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, tint: Color, total: Int64) -> some View {
        HStack(spacing: 16) {
            Text(label).foregroundStyle(Theme.soft).frame(width: 260, alignment: .leading)
            Slider(value: value, in: range, step: 1).tint(tint).frame(maxWidth: 380).accessibilityLabel(label)
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(Int(value.wrappedValue))%").font(Theme.mono(15))
                Text("\(Theme.bytes(total * Int64(value.wrappedValue) / 100)) free").font(.system(size: 11)).foregroundStyle(Theme.tertiary)
            }
            .frame(minWidth: 70, alignment: .trailing)
        }
        .frame(minHeight: 44)
    }

    private var foldersSection: some View {
        @Bindable var cleaner = cleaner
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Folders it may clean").font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("Oldest items go first. Deleted for good, because the Trash doesn't free space.")
                    .font(.system(size: 12)).foregroundStyle(Theme.tertiary)
            }
            VStack(spacing: 0) {
                if cleaner.settings.folders.isEmpty {
                    Text("No folders yet. Nothing will be deleted until you add one.")
                        .foregroundStyle(Theme.secondary).frame(maxWidth: .infinity, minHeight: 58)
                        .overlay(alignment: .bottom) { Theme.divider.frame(height: 1) }
                }
                ForEach($cleaner.settings.folders) { $f in folderRow($f) }
                HStack {
                    addMenu
                    Spacer()
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
            }
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.track))
        }
    }

    private func folderRow(_ f: Binding<WatchedFolder>) -> some View {
        let folder = f.wrappedValue
        let tint = Category.allCases.first { $0.roots.contains { $0.standardizedFileURL == folder.url.standardizedFileURL } }?.color
            ?? Theme.secondary
        let e = eligible[folder.path]
        return HStack(spacing: 0) {
            Toggle("Clean \(folder.name)", isOn: f.enabled).toggleStyle(.switch).labelsHidden().controlSize(.small).tint(Theme.accent)
                .padding(.leading, 14).padding(.trailing, 16)   // breathing room before the folder name
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 3).fill(tint).frame(width: 10, height: 10)
                    Text(folder.name).font(.system(size: 14, weight: .medium))
                }
                Text(folder.url.abbreviatedPath).font(Theme.mono(11, .regular)).foregroundStyle(Theme.tertiary).truncationMode(.middle)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            Group {
                if let e {
                    Text(e.count > 0 ? "\(Theme.plural(e.count, "item")) · \(Theme.bytes(e.bytes))" : "Nothing old enough")
                        .font(e.count > 0 ? Theme.mono(12, .regular) : .system(size: 12))
                        .foregroundStyle(e.count > 0 && folder.enabled ? Theme.text : Theme.tertiary)
                } else {
                    ProgressView().controlSize(.mini)
                }
            }
            .frame(width: 170, alignment: .leading)
            Button { cleaner.settings.folders.removeAll { $0.id == folder.id } } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(GhostButtonStyle()).help("Stop watching this folder").accessibilityLabel("Stop cleaning \(folder.name)")
            .frame(width: 44)
        }
        .frame(minHeight: 58)
        .overlay(alignment: .bottom) { Theme.divider.frame(height: 1) }
    }

    private var addMenu: some View {
        Menu {
            ForEach(Category.allCases.filter { $0 != .largeFiles && $0 != .homeFolder }) { c in
                Button("\(c.name) — \(c.displayPath)") { add(c.roots) }
                    .disabled(c.roots.allSatisfy(watched))
            }
            Divider()
            Button("Other folder…") { pickFolders() }
        } label: {
            Label("Add folder…", systemImage: "plus")
        }
        .menuStyle(.button).menuIndicator(.hidden).fixedSize()
        .buttonStyle(OutlineButtonStyle())
    }

    private var neverTouched: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Never touched, no matter what").font(.system(size: 15, weight: .semibold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 8)], spacing: 8) {
                rule("lock", "Apple and system caches", "com.apple.* and anything macOS refused before. macOS blocks these anyway.")
                rule("clock", "Anything changed in the last 3 days", "One recently changed file keeps its whole folder. Caches are the exception: apps touch them constantly.")
                rule("icloud", "iCloud Drive, Photos and cloud folders", "Synced stuff is never auto-deleted, including Dropbox and Google Drive folders.")
            }
        }
    }

    private func rule(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(Theme.secondary).frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                Text(detail).font(.system(size: 12)).foregroundStyle(Theme.tertiary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Actions

    /// What each folder could free right now. Sizes every eligible item, so it runs off the main thread.
    // ponytail: re-measures every folder whenever the list changes; cache per folder if it gets slow.
    private func measure() async {
        let skip = cleaner.skip
        for f in cleaner.settings.folders where eligible[f.path] == nil {
            let picks = await Task.detached {
                AutoCleaner.isAllowed(f.url)
                    ? AutoCleaner.plan(AutoCleaner.candidates([f]), need: .max, skip: skip, inspect: DiskScanner.inspect) : []
            }.value
            eligible[f.path] = (picks.count, picks.reduce(0) { $0 + $1.item.bytes })
        }
    }

    private func pickFolders() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Watch"
        guard panel.runModal() == .OK else { return }
        add(panel.urls)
    }

    private func watched(_ url: URL) -> Bool {
        cleaner.settings.folders.contains { $0.path == url.standardizedFileURL.path(percentEncoded: false) }
    }

    private func add(_ urls: [URL]) {
        for url in urls where !watched(url) {
            guard AutoCleaner.isAllowed(url) else { refused.append(url.abbreviatedPath); continue }
            cleaner.settings.folders.append(WatchedFolder(path: url.standardizedFileURL.path(percentEncoded: false)))
        }
    }
}
