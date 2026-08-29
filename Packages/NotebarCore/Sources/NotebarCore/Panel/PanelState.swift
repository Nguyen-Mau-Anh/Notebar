import Foundation

public enum PanelState: Equatable, Sendable {
    case hidden
    case expanding
    case expanded
    case collapsing
}

public enum PanelTimer: Equatable, Sendable {
    case edgeDwell
    case exitDwell
}

public enum PollRate: Equatable, Sendable {
    /// Cursor is far from the edge. 10 Hz.
    case idle
    /// Cursor is near the edge or the panel is open. 60 Hz.
    case active
}

public enum PanelEvent: Equatable, Sendable {
    /// Cursor entered the narrow activation strip at the screen edge.
    case cursorEnteredTrigger
    /// Cursor left the activation strip before the dwell elapsed.
    case cursorLeftTrigger
    /// Cursor moved inside the panel's bounds.
    case cursorEnteredPanel
    /// Cursor moved further than `exitSlop` outside the panel's bounds.
    case cursorLeftPanel
    /// The edge-dwell timer fired.
    case edgeDwellElapsed
    /// The exit-dwell timer fired.
    case exitDwellElapsed
    /// A show or hide animation finished.
    case animationFinished
    /// Global hotkey pressed, or the menu bar toggle chosen.
    case toggleRequested
    case escapePressed
}

/// Side effects the reducer requests. `PanelController` is the only code that
/// turns these into real AppKit calls — that separation is what makes every
/// transition testable without a window.
public enum PanelEffect: Equatable, Sendable {
    case startTimer(PanelTimer)
    case cancelTimer(PanelTimer)
    case showPanel
    case hidePanel
    case setPollRate(PollRate)
}

/// The suppression signals from spec section 4.4. Snapshotted by
/// `PanelController` and passed into every `reduce` call.
public struct PanelContext: Equatable, Sendable {
    /// User pinned the panel, or summoned it by hotkey.
    public var isPinned: Bool
    /// A menu, popover, or sheet is open.
    public var hasOpenOverlay: Bool
    /// A drag is in flight.
    public var isDragging: Bool
    /// A text editor holds first responder.
    public var isEditorFocused: Bool
    /// Milliseconds since the last keystroke, or nil if none this session.
    public var msSinceLastKeystroke: Int?
    /// The panel is the key window.
    public var isWindowKey: Bool

    public init(
        isPinned: Bool = false,
        hasOpenOverlay: Bool = false,
        isDragging: Bool = false,
        isEditorFocused: Bool = false,
        msSinceLastKeystroke: Int? = nil,
        isWindowKey: Bool = false
    ) {
        self.isPinned = isPinned
        self.hasOpenOverlay = hasOpenOverlay
        self.isDragging = isDragging
        self.isEditorFocused = isEditorFocused
        self.msSinceLastKeystroke = msSinceLastKeystroke
        self.isWindowKey = isWindowKey
    }

    /// A context with every suppression signal off.
    public static let idle = PanelContext()
}
