import AppKit
import SwiftUI
import Carbon.HIToolbox
import NotebarCore
import NotebarStore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: PanelController?
    private var statusItem: StatusItemController?
    private var hotKey: GlobalHotKey?
    private var model: PanelViewModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Stamped once, first, so every line that follows this run is
        // identifiable by build even from just a fragment of the log (spec
        // §6.4b) — a bug report's log excerpt is useless if it can't be
        // matched to the version that produced it.
        let bundleInfo = Bundle.main.infoDictionary
        let appVersion = bundleInfo?["CFBundleShortVersionString"] as? String ?? "unknown"
        let buildNumber = bundleInfo?["CFBundleVersion"] as? String ?? "unknown"
        NotebarLog.app.info("""
            Notebar \(appVersion, privacy: .public) (\(buildNumber, privacy: .public)) launching on \
            macOS \(ProcessInfo.processInfo.operatingSystemVersionString, privacy: .public)
            """)

        let repositories: NotebarDatabase.Repositories
        do {
            repositories = try NotebarDatabase.openDefault()
        } catch {
            // A permissions or disk problem opening Application Support
            // shouldn't take the whole app down, and must never surface a
            // dialog — spec §1's "no permission prompt on first launch"
            // success criterion. Degrade to in-memory rather than crash;
            // notes just won't survive this run.
            NotebarLog.store.error("could not open the on-disk database, falling back to in-memory: \(String(describing: error), privacy: .public)")
            repositories = try! NotebarDatabase.openInMemory()
        }

        // Applied before `PanelViewModel`/`PanelController` even exist, so
        // it is unquestionably set before `controller.start()` calls
        // `presentHandle()` — spec §6.5's "no visible flash of the wrong
        // appearance". `PanelViewModel.init` reads the same saved value
        // again for its own `theme` property; that second read is cheap and
        // keeps this single-purpose rather than threading a value through.
        let savedTheme: Theme
        do {
            savedTheme = try repositories.appState.theme()
        } catch {
            NotebarLog.store.error("failed to read saved theme, falling back to default: \(String(describing: error), privacy: .public)")
            savedTheme = .default
        }
        NSApp.appearance = savedTheme.nsAppearance

        let model = PanelViewModel(
            noteRepository: repositories.notes,
            openTabRepository: repositories.openTabs,
            taskRepository: repositories.tasks,
            appStateRepository: repositories.appState,
            diagnosticsRepository: repositories.diagnostics
        )
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
            NotebarLog.app.error("global hotkey unavailable — another app may hold Cmd+Shift+Space")
        } else {
            NotebarLog.app.info("global hotkey registered (Cmd+Shift+Space)")
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
