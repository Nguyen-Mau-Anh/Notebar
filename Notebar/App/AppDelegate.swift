import AppKit
import SwiftUI
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: PanelController?
    private var statusItem: StatusItemController?
    private var hotKey: GlobalHotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let model = PanelViewModel()
        let content = NSHostingView(rootView: RootView(model: model))

        let controller = PanelController(content: content, model: model)
        controller.start()
        self.controller = controller

        statusItem = StatusItemController(
            onToggle: { [weak controller] in controller?.toggle() },
            onQuit: { NSApp.terminate(nil) }
        )

        // Cmd+Shift+Space
        hotKey = GlobalHotKey(
            keyCode: UInt32(kVK_Space),
            modifiers: UInt32(cmdKey | shiftKey)
        ) { [weak controller] in
            controller?.toggle()
        }

        if hotKey == nil {
            NSLog("Notebar: global hotkey unavailable — another app may hold Cmd+Shift+Space")
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
