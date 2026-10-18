import SwiftUI

struct FooterBar<Actions: View>: View {
    let note: String
    @ViewBuilder let actions: Actions

    var body: some View {
        HStack(spacing: 14) {
            Text(note).font(.system(size: 13)).foregroundStyle(Theme.secondary)
            Spacer()
            actions
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 16)
        .background(Theme.footer)
        .overlay(alignment: .top) { Theme.divider.frame(height: 1) }
    }
}
