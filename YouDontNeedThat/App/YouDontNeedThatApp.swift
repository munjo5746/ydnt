import SwiftUI
import UserNotifications

@main
struct YouDontNeedThatApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        Window("You Don't Need That", id: "main") {
            RootView().environment(delegate.cleaner).environment(delegate.scan)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 800)

        MenuBarExtra {
            MenuBarPanel().environment(delegate.cleaner).environment(delegate.scan)
        } label: {
            Image(nsImage: .menuBarIcon(dot: delegate.cleaner.lowSpace && delegate.cleaner.settings.enabled,
                                        dim: !delegate.cleaner.settings.enabled))
                .accessibilityLabel(delegate.cleaner.state.detail)
        }
        .menuBarExtraStyle(.window)
    }
}

/// The app lives in the menu bar (LSUIElement); the window is extra.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Unit tests launch the app as their host: never auto-clean the real disk there.
    private static let testing = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    let cleaner = Fixtures.isFake ? Fixtures.demoCleaner() : AutoCleaner(poll: !testing)
    let scan = ScanModel()     // shared by the window and the menu bar popover

    func applicationDidFinishLaunching(_ notification: Notification) {
        AutoCleaner.registerNotifications()
        UNUserNotificationCenter.current().delegate = self
        // Opened at login: stay in the menu bar, don't pop the window.
        let event = NSAppleEventManager.shared().currentAppleEvent
        guard event?.eventID == kAEOpenApplication,
              event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem else { return }
        DispatchQueue.main.async {
            NSApp.windows.filter { $0.identifier?.rawValue.hasPrefix("main") == true }.forEach { $0.close() }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification)
        async -> UNNotificationPresentationOptions { [.banner, .sound] }

    // ponytail: tapping the notification body does nothing; the menu bar banner covers it.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == AutoCleaner.cleanAction else { return }
        await cleaner.check(force: true)
    }
}

extension NSImage {
    /// The side-eye trash can as a template image, plus an amber dot when space is low.
    @MainActor static func menuBarIcon(dot: Bool, dim: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            // Drawn on the design's 24-unit grid.
            NSGraphicsContext.current?.cgContext.scaleBy(x: 0.75, y: 0.75)
            let ink = NSColor.labelColor.withAlphaComponent(dim ? 0.45 : 1)
            ink.set()
            let p = NSBezierPath()
            p.lineWidth = 1.8
            p.lineCapStyle = .round
            p.lineJoinStyle = .round
            p.move(to: NSPoint(x: 4, y: 7)); p.line(to: NSPoint(x: 20, y: 7))
            p.move(to: NSPoint(x: 9.5, y: 7)); p.line(to: NSPoint(x: 9.5, y: 5)); p.line(to: NSPoint(x: 14.5, y: 5)); p.line(to: NSPoint(x: 14.5, y: 7))
            p.move(to: NSPoint(x: 6, y: 9.5)); p.line(to: NSPoint(x: 18, y: 9.5)); p.line(to: NSPoint(x: 17, y: 19.5))
            p.curve(to: NSPoint(x: 15, y: 21.3), controlPoint1: NSPoint(x: 16.9, y: 20.6), controlPoint2: NSPoint(x: 16, y: 21.3))
            p.line(to: NSPoint(x: 9, y: 21.3))
            p.curve(to: NSPoint(x: 7, y: 19.5), controlPoint1: NSPoint(x: 8, y: 21.3), controlPoint2: NSPoint(x: 7.1, y: 20.6))
            p.close()
            p.move(to: NSPoint(x: 12.7, y: 12.2)); p.curve(to: NSPoint(x: 15.8, y: 11.9), controlPoint1: NSPoint(x: 13.8, y: 11.5), controlPoint2: NSPoint(x: 14.8, y: 11.4))
            p.stroke()
            for x in [10.2, 13.9] { NSBezierPath(ovalIn: NSRect(x: x - 1.1, y: 13.5, width: 2.2, height: 2.2)).fill() }
            if dot {
                NSColor(red: 0.95, green: 0.71, blue: 0.27, alpha: 1).set()
                NSBezierPath(ovalIn: NSRect(x: 16.5, y: 0.5, width: 7, height: 7)).fill()
            }
            return true
        }
        // A template can't carry the amber dot; labelColor is resolved per draw, so it still follows the menu bar.
        // ponytail: if the dot ever renders in the wrong menu bar appearance, draw two images and pick by effectiveAppearance.
        image.isTemplate = !dot
        return image
    }
}
