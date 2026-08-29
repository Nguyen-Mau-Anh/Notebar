import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: EdgePanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Temporary verification scaffold — replaced by PanelController in Task 7.
        guard let screen = NSScreen.main else { return }
        let width: CGFloat = 420
        let frame = NSRect(
            x: screen.visibleFrame.maxX - width,
            y: screen.visibleFrame.minY,
            width: width,
            height: screen.visibleFrame.height
        )
        let panel = EdgePanel(contentRect: frame)
        panel.backgroundColor = NSColor.systemRed.withAlphaComponent(0.35)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
