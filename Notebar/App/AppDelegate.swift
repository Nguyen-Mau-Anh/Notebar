import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // LSUIElement in Info.plist already hides the Dock icon; this makes the
        // behaviour explicit and survives someone flipping the plist by accident.
        NSApp.setActivationPolicy(.accessory)
        NSLog("Notebar launched")
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
