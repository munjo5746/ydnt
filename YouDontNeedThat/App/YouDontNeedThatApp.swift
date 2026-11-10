import SwiftUI

@main
struct YouDontNeedThatApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var cleaner = AutoCleaner()

    var body: some Scene {
        Window("You Don't Need That", id: "main") {
            RootView().environment(cleaner)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1160, height: 760)

        MenuBarExtra {
            MenuBarPanel().environment(cleaner)
        } label: {
            Image(nsImage: .menuBarIcon(badge: cleaner.state.badge))
                .accessibilityLabel(cleaner.state.detail)
        }
        .menuBarExtraStyle(.window)
    }
}

/// The app lives in the menu bar (LSUIElement); the window is extra.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Opened at login: stay in the menu bar, don't pop the window.
        let event = NSAppleEventManager.shared().currentAppleEvent
        guard event?.eventID == kAEOpenApplication,
              event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem else { return }
        DispatchQueue.main.async {
            NSApp.windows.filter { $0.identifier?.rawValue.hasPrefix("main") == true }.forEach { $0.close() }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

extension NSImage {
    /// "nah." plus an optional SF Symbol badge, as one template image so the menu bar tints it.
    @MainActor static func menuBarIcon(badge: String?) -> NSImage {
        let base = NSImage(named: "MenuBarIcon")!
        guard let badge, let symbol = NSImage(systemSymbolName: badge, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 10, weight: .bold)) else { return base }
        let size = NSSize(width: base.size.width + 2 + symbol.size.width, height: base.size.height)
        let image = NSImage(size: size, flipped: false) { _ in
            base.draw(in: NSRect(origin: .zero, size: base.size))
            symbol.draw(in: NSRect(x: base.size.width + 2, y: (size.height - symbol.size.height) / 2,
                                   width: symbol.size.width, height: symbol.size.height))
            return true
        }
        image.isTemplate = true
        return image
    }
}
