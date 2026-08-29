import SwiftUI

@main
struct NotebarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The panel is an NSPanel owned by AppDelegate, not a SwiftUI Scene,
        // because SwiftUI has no equivalent for a non-activating floating panel.
        // Settings{} gives the app a valid empty scene graph.
        Settings { EmptyView() }
    }
}
