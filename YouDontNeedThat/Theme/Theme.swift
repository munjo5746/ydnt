import SwiftUI

enum Theme {
    static let window = Color(hex: 0x141518)
    static let titleBar = Color(hex: 0x101114)
    static let footer = Color(hex: 0x111215)
    static let divider = Color(hex: 0x26282D)
    static let rowActive = Color(hex: 0x22242A)
    static let text = Color(hex: 0xECEDEF)
    static let secondary = Color(hex: 0x9A9CA3)
    static let tertiary = Color(hex: 0x8A8C93)
    static let accent = Color(hex: 0xC6F24E)
    static let border = Color(hex: 0x3A3C43)

    static func bytes(_ b: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: b, countStyle: .file)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }
}

struct OutlineButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14))
            .padding(.horizontal, 16)
            .frame(minHeight: 40)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
    }
}

struct AccentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(Theme.window)
            .padding(.horizontal, 18)
            .frame(minHeight: 40)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 8))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
    }
}
