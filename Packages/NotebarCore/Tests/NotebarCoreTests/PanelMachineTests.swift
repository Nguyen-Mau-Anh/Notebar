import Testing
@testable import NotebarCore

@Suite("PanelMachine transitions")
struct PanelMachineTransitionTests {

    @Test("entering the trigger zone starts the dwell timer but does not expand")
    func enteringTriggerStartsDwell() {
        let (state, effects) = PanelMachine.reduce(.hidden, .cursorEnteredTrigger, .idle)
        #expect(state == .hidden)
        #expect(effects.contains(.startTimer(.edgeDwell)))
        #expect(effects.contains(.setPollRate(.active)))
    }

    @Test("leaving the trigger zone before dwell cancels the timer")
    func leavingTriggerCancelsDwell() {
        let (state, effects) = PanelMachine.reduce(.hidden, .cursorLeftTrigger, .idle)
        #expect(state == .hidden)
        #expect(effects.contains(.cancelTimer(.edgeDwell)))
        #expect(effects.contains(.setPollRate(.idle)))
    }

    @Test("dwell elapsing expands the panel")
    func dwellElapsedExpands() {
        let (state, effects) = PanelMachine.reduce(.hidden, .edgeDwellElapsed, .idle)
        #expect(state == .expanding)
        #expect(effects.contains(.showPanel))
    }

    @Test("animation finishing completes the expansion")
    func expandingCompletes() {
        let (state, _) = PanelMachine.reduce(.expanding, .animationFinished, .idle)
        #expect(state == .expanded)
    }

    @Test("leaving the panel starts the exit timer, it does not collapse immediately")
    func leavingPanelStartsExitTimer() {
        let (state, effects) = PanelMachine.reduce(.expanded, .cursorLeftPanel, .idle)
        #expect(state == .expanded)
        #expect(effects.contains(.startTimer(.exitDwell)))
        #expect(!effects.contains(.hidePanel))
    }

    @Test("returning to the panel cancels a pending collapse")
    func returningCancelsExitTimer() {
        let (state, effects) = PanelMachine.reduce(.expanded, .cursorEnteredPanel, .idle)
        #expect(state == .expanded)
        #expect(effects.contains(.cancelTimer(.exitDwell)))
    }

    @Test("exit dwell elapsing collapses the panel")
    func exitDwellCollapses() {
        let (state, effects) = PanelMachine.reduce(.expanded, .exitDwellElapsed, .idle)
        #expect(state == .collapsing)
        #expect(effects.contains(.hidePanel))
    }

    @Test("collapse animation finishing returns to hidden and slows polling")
    func collapseCompletes() {
        let (state, effects) = PanelMachine.reduce(.collapsing, .animationFinished, .idle)
        #expect(state == .hidden)
        #expect(effects.contains(.setPollRate(.idle)))
    }

    @Test("re-entering during collapse reverses it")
    func reEntryDuringCollapseReverses() {
        let (state, effects) = PanelMachine.reduce(.collapsing, .cursorEnteredPanel, .idle)
        #expect(state == .expanding)
        #expect(effects.contains(.showPanel))
    }

    @Test("escape collapses even when pinned")
    func escapeAlwaysCollapses() {
        let pinned = PanelContext(isPinned: true)
        let (state, effects) = PanelMachine.reduce(.expanded, .escapePressed, pinned)
        #expect(state == .collapsing)
        #expect(effects.contains(.hidePanel))
    }

    @Test("toggle opens when hidden and closes when expanded")
    func toggleFlips() {
        let (opened, openEffects) = PanelMachine.reduce(.hidden, .toggleRequested, .idle)
        #expect(opened == .expanding)
        #expect(openEffects.contains(.showPanel))

        let (closed, closeEffects) = PanelMachine.reduce(.expanded, .toggleRequested, .idle)
        #expect(closed == .collapsing)
        #expect(closeEffects.contains(.hidePanel))
    }

    @Test("unhandled pairs are inert")
    func unhandledPairsAreInert() {
        let (state, effects) = PanelMachine.reduce(.hidden, .exitDwellElapsed, .idle)
        #expect(state == .hidden)
        #expect(effects.isEmpty)
    }
}
