import AppKit
import SwiftUI

/// Hosting view that lets the first click through to SwiftUI content.
///
/// `EdgePanel` is `.nonactivatingPanel`, which is what lets the panel take
/// keystrokes without activating the app. The cost is AppKit's default:
/// a click into a non-key window is consumed granting focus and never reaches
/// the content, so every tab switch needs two clicks. Overriding this delivers
/// that first click.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    required init(rootView: Content) {
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
