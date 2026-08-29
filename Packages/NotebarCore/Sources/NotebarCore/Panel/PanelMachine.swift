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
    /// (see CollapsePolicyTests); the last three are judgment.
    ///
    /// Worth deciding explicitly: should a focused editor with no recent typing
    /// keep the panel open indefinitely, or should the grace period win? And is
    /// `isWindowKey` alone enough to suppress, given a panel can be key simply
    /// because you clicked it once?
    static func shouldCollapse(_ context: PanelContext) -> Bool {
        // ─────────────────────────────────────────────────────────────
        // PROVISIONAL — the three signals below are deliberately unused.
        // The hard invariants above are settled (see CollapsePolicyTests).
        // What is NOT settled, and is the app author's call:
        //   · isEditorFocused      — should a focused editor with no recent
        //                            typing hold the panel open indefinitely,
        //                            or should PanelTiming.typingGrace win?
        //   · msSinceLastKeystroke — is 2.0s the right grace period?
        //   · isWindowKey          — is being key enough to suppress, given a
        //                            panel can be key just from one stray click?
        // Until that is decided, this policy ignores all three.
        // ─────────────────────────────────────────────────────────────
        if context.isPinned || context.hasOpenOverlay || context.isDragging {
            return false
        }
        return true
    }
}
