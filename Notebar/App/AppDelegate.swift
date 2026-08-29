import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: PanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Placeholder content, replaced by RootView in Task 8.
        let placeholder = NSHostingView(
            rootView: Color.blue.opacity(0.25).ignoresSafeArea()
        )

        let controller = PanelController(content: placeholder)
        controller.start()
        self.controller = controller
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
