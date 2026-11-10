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
            Image("MenuBarIcon")
            if let text = cleaner.state.menuText { Text(text) }
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
