import Foundation

/// The panel's behaviour as a pure function.
///
/// This type must never import AppKit, hold state, read a clock, or start a
/// timer. Time enters only as events (`edgeDwellElapsed`, `exitDwellElapsed`)
/// that `PanelController` schedules on the reducer's instruction. That is what
/// makes flicker scenarios — the bugs that are miserable to reproduce by
/// hand — into ordinary table tests.
public enum PanelMachine {

    public static func reduce(
        _ state: PanelState,
        _ event: PanelEvent,
        _ context: PanelContext
    ) -> (PanelState, [PanelEffect]) {

        switch (state, event) {

        // Approaching the edge: arm the dwell timer, speed up polling.
        case (.hidden, .cursorEnteredTrigger):
            return (.hidden, [.startTimer(.edgeDwell), .setPollRate(.active)])

        case (.hidden, .cursorLeftTrigger):
            return (.hidden, [.cancelTimer(.edgeDwell), .setPollRate(.idle)])

        case (.hidden, .edgeDwellElapsed):
            return (.expanding, [.showPanel])

        case (.expanding, .animationFinished):
            return (.expanded, [])

        // Leaving an open panel only *arms* the collapse. Whether it is allowed
        // to fire is decided when the timer elapses, against a fresh context.
        case (.expanded, .cursorLeftPanel):
            guard shouldCollapse(context) else { return (.expanded, []) }
            return (.expanded, [.startTimer(.exitDwell)])

        case (.expanded, .cursorEnteredPanel):
            return (.expanded, [.cancelTimer(.exitDwell)])

        case (.expanded, .exitDwellElapsed):
            guard shouldCollapse(context) else { return (.expanded, []) }
            return (.collapsing, [.hidePanel])

        case (.collapsing, .animationFinished):
            return (.hidden, [.setPollRate(.idle)])

        // Cursor came back mid-collapse: reverse without touching hidden.
        case (.collapsing, .cursorEnteredPanel), (.collapsing, .cursorEnteredTrigger):
            return (.expanding, [.showPanel])

        // Escape overrides every suppression signal, pinning included (spec 4.3).
        case (.expanded, .escapePressed), (.expanding, .escapePressed):
            return (.collapsing, [.hidePanel, .cancelTimer(.exitDwell)])

        case (.hidden, .toggleRequested), (.collapsing, .toggleRequested):
            return (.expanding, [.showPanel, .setPollRate(.active)])

        case (.expanded, .toggleRequested), (.expanding, .toggleRequested):
            return (.collapsing, [.hidePanel])

        default:
            return (state, [])
        }
    }

    /// Decides whether the panel is allowed to collapse right now.
    ///
    /// Called twice per collapse: once when the cursor leaves (to decide whether
    /// to arm the exit timer at all) and again when that timer elapses (against a
    /// fresh context, because things may have changed in 350 ms).
    ///
    /// Available signals on `context`:
    ///   - `isPinned`              user pinned it, or summoned it by hotkey
    ///   - `hasOpenOverlay`        a menu, popover, or sheet is open
    ///   - `isDragging`            a drag is in flight
    ///   - `isEditorFocused`       a text editor holds first responder
    ///   - `msSinceLastKeystroke`  milliseconds since last keypress, nil if none
    ///   - `isWindowKey`           the panel is the key window
    ///
    /// `PanelTiming.typingGrace` is 2.0 seconds.
    ///
    /// The trade-off: collapsing eagerly keeps the screen clean but interrupts
    /// you mid-thought; collapsing lazily never interrupts but leaves the panel
    /// loitering over your work. The first three signals are hard requirements
    /// (see CollapsePolicyTests). Of the remaining three, the decision made
    /// here:
    ///   · isEditorFocused      — holds the panel open indefinitely, no grace
    ///                            period involved. Losing what you are typing
    ///                            because the mouse drifted is the worst
    ///                            failure this panel can have, and clicking
    ///                            into another app clears focus anyway, so
    ///                            this cannot strand the panel open.
    ///   · msSinceLastKeystroke — once focus is gone, `typingGrace` still
    ///                            covers a recent burst of typing.
    ///   · isWindowKey          — deliberately left unused. A panel can be
    ///                            key from one stray click, which is too weak
    ///                            a signal to suppress collapse on.
    static func shouldCollapse(_ context: PanelContext) -> Bool {
        // Hard invariants — never collapse under these.
        if context.isPinned || context.hasOpenOverlay || context.isDragging { return false }

        // A focused editor holds the panel open. Losing what you are typing because
        // the mouse drifted is the worst failure this panel can have, and clicking
        // into another app clears focus anyway, so this cannot strand the panel open.
        if context.isEditorFocused { return false }

        // Recently typed, even if focus has since gone: still working.
        if let ms = context.msSinceLastKeystroke,
           Double(ms) / 1000 <= PanelTiming.typingGrace {
            return false
        }

        return true
    }
}
