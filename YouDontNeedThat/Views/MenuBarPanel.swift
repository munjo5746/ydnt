import SwiftUI

/// What drops down from the menu bar icon.
struct MenuBarPanel: View {
    @Environment(AutoCleaner.self) private var cleaner
    @Environment(ScanModel.self) private var scan
    @Environment(\.openWindow) private var openWindow

    private var thisMonth: [History.Run] {
        cleaner.history.runs.filter { Calendar.current.isDate($0.date, equalTo: .now, toGranularity: .month) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if let d = cleaner.disk { storage(d) }
            summary
            if !scan.results.isEmpty { biggest }
            recent
            footer
        }
        .font(.system(size: 13))
        .padding(16)
        .frame(width: 372)
        .background(Color(hex: 0x1E1F23))
        .foregroundStyle(Theme.text)
        .preferredColorScheme(.dark)
        .onAppear {
            cleaner.refreshDisk()
            if scan.results.isEmpty { scan.scanAll() }
        }
    }

    private var header: some View {
        let (pill, fg, bg): (String, Color, Color) =
            !cleaner.settings.enabled ? ("Paused", Theme.soft, Color(hex: 0x2E3035))
            : cleaner.state.alert ? ("Low space", Theme.amber, Color(hex: 0x3A2F17))
            : ("Watching", Theme.accent, Color(hex: 0x2B3319))
        return HStack(spacing: 10) {
            LogoMark(size: 28, plate: Color(hex: 0x2A2C31))
            Text("You Don't Need \(Text("That").foregroundStyle(Theme.accent))").font(.system(size: 14, weight: .heavy)).tracking(-0.4)
            Spacer()
            Text(pill).font(.system(size: 11, weight: .semibold)).foregroundStyle(fg)
                .padding(.horizontal, 9).padding(.vertical, 3).background(bg, in: Capsule())
        }
    }

    private func storage(_ d: DiskSpace) -> some View {
        let s = cleaner.settings
        let low = d.free * 100 < Double(s.thresholdPercent)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(Theme.bytes(d.available)).font(Theme.mono(24))
                Text("free").foregroundStyle(Theme.secondary)
                Spacer()
                Text("of \(Theme.bytes(d.total)) · Macintosh HD").font(.system(size: 12)).foregroundStyle(Theme.tertiary)
            }
            SpaceBar(free: d.free, start: s.thresholdPercent, stop: s.stopPercent)
            HStack(spacing: 14) {
                MarkerLegend(color: Theme.amber, text: "Starts below \(s.thresholdPercent)% (\(Theme.bytes(d.total * Int64(s.thresholdPercent) / 100)))")
                MarkerLegend(color: Theme.text, text: "Stops at \(s.stopPercent)%")
            }
            .font(.system(size: 11)).foregroundStyle(Theme.secondary)
            if s.enabled, low, let line = lowLine {
                HStack(spacing: 10) {
                    Text(line).font(.system(size: 12)).foregroundStyle(Theme.amber).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if case .waiting(_, let b, _) = cleaner.state {
                        Button("Clean \(Theme.bytes(b))") { Task { await cleaner.check(force: true) } }
                            .buttonStyle(AccentButtonStyle(height: 30))
                    }
                }
                .padding(.top, 10)
                .overlay(alignment: .top) { Color(hex: 0x3A3226).frame(height: 1) }
            }
        }
        .padding(14)
        .background(low ? Color(hex: 0x2A2519) : Color(hex: 0x25272C), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(low ? Color(hex: 0x4A3D22) : Color(hex: 0x2E3035)))
    }

    private var lowLine: String? {
        let below = cleaner.settings.thresholdPercent
        switch cleaner.state {
        case .waiting(_, _, let n): return "You're under \(below)%. \(Theme.plural(n, "old item")) can go."
        case .stuck: return "You're under \(below)% and nothing in your folders is old enough to go."
        case .low, .planning, .deleting: return cleaner.state.detail
        default: return nil
        }
    }

    private var summary: some View {
        HStack(spacing: 8) {
            tile("Could free", scan.scannedAt == nil ? "…" : Theme.bytes(scan.reclaimable), Theme.text)
            tile("Freed in \(Date.now.formatted(.dateTime.month(.abbreviated)))", Theme.bytes(thisMonth.reduce(0) { $0 + $1.freed }), Theme.accent)
            tile("Auto-cleans", "\(thisMonth.filter(\.auto).count) this month", Theme.text)
        }
    }

    private func tile(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.tertiary)
            Text(value).font(Theme.mono(15)).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Color(hex: 0x25272C), in: RoundedRectangle(cornerRadius: 9))
    }

    private var biggest: some View {
        let top = Category.allCases
            .map { c in (c, scan.results[c]?.items.filter { !$0.isProtected }.reduce(0) { $0 + $1.bytes } ?? 0) }
            .filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }.prefix(3)
        let max = Double(top.first?.1 ?? 1)
        return VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Biggest clutter")
            if top.isEmpty {
                Text(scan.isScanning ? "Judging your files…" : "Nothing worth cleaning.").font(.system(size: 12)).foregroundStyle(Theme.tertiary)
            }
            ForEach(Array(top), id: \.0) { c, bytes in
                HStack(spacing: 10) {
                    HStack(spacing: 7) {
                        RoundedRectangle(cornerRadius: 2).fill(c.color).frame(width: 8, height: 8)
                        Text(c.name).lineLimit(1)
                    }
                    .frame(width: 120, alignment: .leading)
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color(hex: 0x2E3035))
                            Capsule().fill(c.color).frame(width: g.size.width * Double(bytes) / max)
                        }
                    }
                    .frame(height: 4)
                    Text(Theme.bytes(bytes)).font(Theme.mono(12)).frame(width: 64, alignment: .trailing)
                }
            }
        }
    }

    private var recent: some View {
        let runs = cleaner.history.runs.filter(\.auto).prefix(3)
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                SectionLabel("Recently auto-cleaned")
                Spacer()
                Button("See all") { open(.history(run: nil)) }.buttonStyle(GhostButtonStyle(tint: Theme.accent, size: 24))
                    .font(.system(size: 12))
            }
            .padding(.bottom, 4)
            if runs.isEmpty {
                Text("Nothing yet. It steps in when space runs low.").font(.system(size: 12)).foregroundStyle(Theme.tertiary)
            }
            ForEach(Array(runs)) { run in
                Button { open(.history(run: run.id)) } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(run.date.formatted(date: .abbreviated, time: .shortened)).fontWeight(.medium)
                            Text("\(Theme.plural(run.succeeded.count, "item")) from \(run.places.joined(separator: ", "))"
                                 + (run.failed > 0 ? " · \(run.failed) skipped" : ""))
                                .font(.system(size: 11)).foregroundStyle(Theme.tertiary).lineLimit(1)
                        }
                        Spacer()
                        Text(Theme.bytes(run.freed)).font(Theme.mono(13))
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4).frame(minHeight: 42)
                    .hoverFill(Color(hex: 0x25272C))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, -8)
                .help("Show this run")
            }
        }
    }

    private var footer: some View {
        @Bindable var cleaner = cleaner
        return HStack(spacing: 8) {
            Button("Open app") { open(nil) }
                .buttonStyle(AccentButtonStyle(fill: Color(hex: 0x33353B), ink: Theme.text, height: 32))
            Button(cleaner.settings.enabled ? "Pause auto-clean" : "Resume auto-clean") { cleaner.settings.enabled.toggle() }
                .buttonStyle(OutlineButtonStyle())
            Spacer()
            Menu {
                Toggle("Open at Login", isOn: Binding(get: { cleaner.launchAtLogin }, set: { cleaner.launchAtLogin = $0 }))
                Divider()
                Button("Quit You Don't Need That") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .frame(width: 32, height: 32)
            .accessibilityLabel("Settings and quit")
        }
        .padding(.top, 12)
        .overlay(alignment: .top) { Color(hex: 0x2E3035).frame(height: 1) }
    }

    private func open(_ screen: Screen?) {
        cleaner.pendingScreen = screen
        openWindow(id: "main")
        NSApp.activate()
    }
}
