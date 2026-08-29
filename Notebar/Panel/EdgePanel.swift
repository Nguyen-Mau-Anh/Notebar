import AppKit

/// The floating overlay window.
///
/// `NSPanel` rather than `NSWindow`, and specifically `.nonactivatingPanel`:
/// that style mask is what lets the panel accept keystrokes *without*
/// activating the application, so typing a note does not disturb whatever app
/// the user was actually working in (spec section 4.1).
final class EdgePanel: NSPanel {

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating

        // .fullScreenAuxiliary is what allows appearing over fullscreen apps;
        // .canJoinAllSpaces follows the user across Spaces (spec section 4.1).
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        // Visibility is owned by PanelController's state machine, not by AppKit.
        hidesOnDeactivate = false
        animationBehavior = .none

        isMovableByWindowBackground = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isReleasedWhenClosed = false
    }

    // A borderless window refuses key status unless this is overridden, which
    // would make every text field in the panel unusable.
    override var canBecomeKey: Bool { true }

    // Main status would put the panel in the window menu and the app switcher.
    override var canBecomeMain: Bool { false }
}
