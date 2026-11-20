import SwiftUI

enum Theme {
    static let window = Color(hex: 0x16171A)
    static let sidebar = Color(hex: 0x0F1012)
    static let bar = Color(hex: 0x121316)       // bottom action bars
    static let card = Color(hex: 0x1B1D21)
    static let raised = Color(hex: 0x1C1E22)    // sheets, hovered rows
    static let hover = Color(hex: 0x24262B)
    static let active = Color(hex: 0x26282D)    // selected nav item
    static let divider = Color(hex: 0x25272C)
    static let rowDivider = Color(hex: 0x222428)
    static let track = Color(hex: 0x2A2C31)
    static let usedSpace = Color(hex: 0x5B5E66)
    static let text = Color(hex: 0xEDEEF0)
    static let soft = Color(hex: 0xC9CBD0)
    static let secondary = Color(hex: 0xA9ABB2)
    static let tertiary = Color(hex: 0x8E9198)
    static let border = Color(hex: 0x3A3C43)
    static let accent = Color(hex: 0xC6F24E)
    static let amber = Color(hex: 0xF2C979)     // "starts below" marker, warnings
    static let warn = Color(hex: 0xE8A33D)      // free-space bar when low
    static let danger = Color(hex: 0xD93F36)
    static let ink = Color(hex: 0x141518)       // text on accent

    static func bytes(_ b: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: b, countStyle: .file)
    }

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// "Today", "3 days ago", "2 months ago".
    static func age(_ date: Date?, now: Date = .now) -> String {
        guard let date else { return "" }
        let d = Int(now.timeIntervalSince(date) / 86_400)
        func n(_ v: Int, _ w: String) -> String { "\(v) \(w)\(v == 1 ? "" : "s") ago" }
        switch d {
        case ..<1: return "Today"
        case 1: return "Yesterday"
        case ..<7: return "\(d) days ago"
        case ..<30: return n(Int((Double(d) / 7).rounded()), "week")
        case ..<365: return n(Int((Double(d) / 30).rounded()), "month")
        default: return n(Int((Double(d) / 365).rounded()), "year")
        }
    }

    static func plural(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }
}

struct HoverFill: ViewModifier {
    var color = Theme.hover
    var radius: CGFloat = 7
    @State private var on = false
    func body(content: Content) -> some View {
        content
            .background(on ? color : .clear, in: RoundedRectangle(cornerRadius: radius))
            .onHover { on = $0 }
    }
}

extension View {
    func hoverFill(_ color: Color = Theme.hover, radius: CGFloat = 7) -> some View {
        modifier(HoverFill(color: color, radius: radius))
    }
}

struct OutlineButtonStyle: ButtonStyle {
    var tint = Theme.text
    var stroke = Theme.border
    var height: CGFloat = 32
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12))
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .frame(minHeight: height)
            .hoverFill()
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(stroke))
            .contentShape(Rectangle())
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
    }
}

struct AccentButtonStyle: ButtonStyle {
    var fill = Theme.accent
    var ink = Theme.ink
    var height: CGFloat = 36
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(ink)
            .padding(.horizontal, 16)
            .frame(minHeight: height)
            .background(fill, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
    }
}

/// Borderless icon or text button that only shows a fill on hover.
struct GhostButtonStyle: ButtonStyle {
    var tint = Theme.secondary
    var size: CGFloat = 32
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(tint)
            .frame(minWidth: size, minHeight: size)
            .hoverFill()
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Pill toggle used for filters and the ask/just-do-it choice.
struct Chip: View {
    let label: String
    let on: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: on ? .semibold : .regular))
                .foregroundStyle(on ? Theme.ink : Color(hex: 0xE2E3E6))
                .padding(.horizontal, 13).frame(minHeight: 32)
                .background(on ? Theme.accent : .clear, in: Capsule())
                .overlay(Capsule().stroke(on ? Theme.accent : Theme.border))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(0.6).foregroundStyle(Theme.tertiary)
    }
}

/// Disk bar: used space from the left, free space on the right, with optional start/stop markers (in % free).
struct SpaceBar: View {
    let free: Double            // 0...1
    var start: Int? = nil
    var stop: Int? = nil
    var height: CGFloat = 10

    var body: some View {
        let low = start.map { free * 100 < Double($0) } ?? false
        GeometryReader { g in
            let w = g.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                UnevenRoundedRectangle(topLeadingRadius: height / 2, bottomLeadingRadius: height / 2)
                    .fill(Theme.usedSpace).frame(width: w * (1 - free))
                UnevenRoundedRectangle(bottomTrailingRadius: height / 2, topTrailingRadius: height / 2)
                    .fill(low ? Theme.warn : Theme.accent).frame(width: w * free)
                    .offset(x: w * (1 - free))
                if let start { mark(start, Theme.amber, w) }
                if let stop { mark(stop, Theme.text, w) }
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("\(Int((free * 100).rounded()))% free")
    }

    private func mark(_ pct: Int, _ color: Color, _ w: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 1).fill(color)
            .frame(width: 2, height: height + 6)
            .offset(x: w * (1 - Double(pct) / 100) - 1)
    }
}

struct MarkerLegend: View {
    let color: Color
    let text: String
    var body: some View {
        HStack(spacing: 6) {
            Rectangle().fill(color).frame(width: 2, height: 11)
            Text(text)
        }
    }
}

// MARK: Brand

/// The side-eye trash can, drawn on a 100×100 grid.
struct LogoMark: View {
    var size: CGFloat = 40
    var plate = Color(hex: 0x24262B)

    var body: some View {
        Canvas { ctx, sz in
            ctx.scaleBy(x: sz.width / 100, y: sz.height / 100)
            let a = GraphicsContext.Shading.color(Theme.accent)
            let dark = GraphicsContext.Shading.color(Theme.ink)
            let line = { (w: CGFloat) in StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round) }
            ctx.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: 100, height: 100), cornerRadius: 23), with: .color(plate))
            ctx.stroke(Path { p in p.addLines([CGPoint(x: 42, y: 24), CGPoint(x: 42, y: 20), CGPoint(x: 58, y: 20), CGPoint(x: 58, y: 24)]) },
                       with: a, style: line(3.5))
            ctx.fill(Path(roundedRect: CGRect(x: 22, y: 24, width: 56, height: 8), cornerRadius: 4), with: a)
            ctx.fill(Path { p in
                p.move(to: CGPoint(x: 27, y: 36)); p.addLine(to: CGPoint(x: 73, y: 36)); p.addLine(to: CGPoint(x: 69, y: 76))
                p.addQuadCurve(to: CGPoint(x: 63, y: 81.5), control: CGPoint(x: 68.5, y: 81.5))
                p.addLine(to: CGPoint(x: 37, y: 81.5))
                p.addQuadCurve(to: CGPoint(x: 31, y: 76), control: CGPoint(x: 31.5, y: 81.5))
                p.closeSubpath()
            }, with: a)
            for x in [33.0, 51.0] { ctx.fill(Path(ellipseIn: CGRect(x: x, y: 48.5, width: 16, height: 15)), with: .color(Color(hex: 0xF4F5F7))) }
            for x in [45.5, 63.5] { ctx.fill(Path(ellipseIn: CGRect(x: x - 3.6, y: 54.9, width: 7.2, height: 7.2)), with: dark) }
            ctx.fill(Path(CGRect(x: 32, y: 47, width: 18, height: 7.5)), with: a)
            ctx.fill(Path(CGRect(x: 50, y: 47, width: 18, height: 4)), with: a)
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: 33.5, y: 54.5)); p.addLine(to: CGPoint(x: 48.5, y: 54.5))
                p.move(to: CGPoint(x: 51.5, y: 51)); p.addLine(to: CGPoint(x: 66.5, y: 51))
                p.move(to: CGPoint(x: 44.5, y: 71.5)); p.addLine(to: CGPoint(x: 55.5, y: 71.5))
            }, with: dark, style: line(2.4))
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: 51.5, y: 44.5)); p.addQuadCurve(to: CGPoint(x: 67, y: 43), control: CGPoint(x: 59.5, y: 39))
            }, with: dark, style: line(2.6))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// "You Don't / Need That", with the logo and its "nah." bubble.
struct BrandLockup: View {
    var body: some View {
        HStack(spacing: 14) {
            LogoMark(plate: Color(hex: 0x24262B))
                .overlay(alignment: .topTrailing) {
                    Text("nah.").font(.system(size: 9, weight: .heavy, design: .rounded)).tracking(-0.3)
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 4).frame(height: 15)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.sidebar, lineWidth: 1.5))
                        .offset(x: 14, y: -12)
                }
            VStack(alignment: .leading, spacing: -2) {
                Text("You Don't")
                Text("Need \(Text("That").foregroundStyle(Theme.accent))")
            }
            .font(.system(size: 18, weight: .heavy)).tracking(-0.7)
            .lineLimit(1).fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("You Don't Need That")
    }
}
