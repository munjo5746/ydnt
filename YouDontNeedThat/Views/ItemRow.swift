import SwiftUI

enum Check { case off, mixed, on }

/// One row in Clean up: a category at the top level, a file or folder inside one.
struct ItemRow: View {
    let name: String
    let path: String
    let bytes: Int64
    let barFraction: Double
    let color: Color
    let modified: Date?
    var meta = ""               // "12 items" under Last used
    var tag: String? = nil      // "Protected by macOS", "2 protected"
    let isFolder: Bool
    let check: Check
    let selectable: Bool        // false: show a lock instead of a checkbox
    var checkLocked = false     // true: on because a parent folder is queued
    let onCheck: () -> Void
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if selectable {
                    Button(action: onCheck) { CheckBox(check: check) }
                        .buttonStyle(GhostButtonStyle(size: 36))
                        .disabled(checkLocked)
                        .accessibilityLabel("Select \(name)")
                        .accessibilityValue(check == .on ? "selected" : check == .mixed ? "partly selected" : "not selected")
                } else {
                    Image(systemName: "lock").font(.system(size: 13)).foregroundStyle(Theme.tertiary)
                        .accessibilityLabel("Protected by macOS")
                }
            }
            .frame(width: 44)

            Button(action: onOpen) {
                HStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Image(systemName: isFolder ? "folder" : "doc").font(.system(size: 13))
                            .foregroundStyle(color)
                            .frame(width: 30, height: 30)
                            .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 7))
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Text(name).font(.system(size: 14, weight: .medium)).truncationMode(.middle)
                                if let tag {
                                    Text(tag).font(.system(size: 11)).foregroundStyle(Theme.soft)
                                        .padding(.horizontal, 7).padding(.vertical, 2).background(Theme.track, in: Capsule())
                                        .fixedSize()
                                }
                            }
                            Text(path).font(Theme.mono(11, .regular)).foregroundStyle(Theme.tertiary).truncationMode(.middle)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 12)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(Theme.age(modified)).foregroundStyle(Theme.soft)
                        if !meta.isEmpty { Text(meta).font(.system(size: 11)).foregroundStyle(Theme.tertiary) }
                    }
                    .frame(width: 120, alignment: .leading)

                    VStack(alignment: .trailing, spacing: 6) {
                        Text(Theme.bytes(bytes)).font(Theme.mono(14))
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.track)
                                Capsule().fill(color).frame(width: max(2, g.size.width * barFraction))
                            }
                        }
                        .frame(width: 120, height: 3)
                    }
                    .frame(width: 170, alignment: .trailing)

                    Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(Theme.tertiary)
                        .opacity(isFolder ? 1 : 0).frame(width: 34)
                }
                .lineLimit(1)
                .padding(.vertical, 6).frame(minHeight: 56)
                .hoverFill(Theme.raised, radius: 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: 13))
        .overlay(alignment: .bottom) { Theme.rowDivider.frame(height: 1) }
    }
}

struct CheckBox: View {
    let check: Check
    var body: some View {
        let on = check != .off
        RoundedRectangle(cornerRadius: 5)
            .fill(on ? Theme.accent : .clear)
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(on ? Theme.accent : Color(hex: 0x6A6D75), lineWidth: 1.5))
            .overlay {
                if on {
                    Image(systemName: check == .on ? "checkmark" : "minus").font(.system(size: 10, weight: .black))
                        .foregroundStyle(Theme.ink)
                }
            }
            .frame(width: 18, height: 18)
    }
}
