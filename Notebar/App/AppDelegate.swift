import AppKit
import SwiftUI
import Carbon.HIToolbox
import NotebarStore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: PanelController?
    private var statusItem: StatusItemController?
    private var hotKey: GlobalHotKey?
    private var model: PanelViewModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let repositories: NotebarDatabase.Repositories
        do {
            repositories = try NotebarDatabase.openDefault()
        } catch {
            // A permissions or disk problem opening Application Support
            // shouldn't take the whole app down, and must never surface a
            // dialog — spec §1's "no permission prompt on first launch"
            // success criterion. Degrade to in-memory rather than crash;
            // notes just won't survive this run.
            NSLog("Notebar: could not open the on-disk database, falling back to in-memory — \(error)")
            repositories = try! NotebarDatabase.openInMemory()
        }

        let model = PanelViewModel(noteRepository: repositories.notes, openTabRepository: repositories.openTabs)
        self.model = model
        let content = FirstMouseHostingView(rootView: RootView(model: model))

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

    /// Flushes any note save still waiting out its debounce, so quitting
    /// within 400ms of the last keystroke never loses it (see
    /// `PanelViewModel.flushAllPendingSaves`).
    func applicationWillTerminate(_ notification: Notification) {
        model?.flushAllPendingSaves()
    }
}
