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

    // Replaced properly in Task 3.
    static func shouldCollapse(_ context: PanelContext) -> Bool { true }
}
