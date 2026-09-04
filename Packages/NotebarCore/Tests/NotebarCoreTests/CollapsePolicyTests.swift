import Testing
@testable import NotebarCore

@Suite("Collapse suppression invariants")
struct CollapsePolicyInvariantTests {

    @Test("a pinned panel never collapses on cursor exit")
    func pinnedNeverCollapses() {
        #expect(PanelMachine.shouldCollapse(PanelContext(isPinned: true)) == false)
    }

    @Test("a panel with an open menu never collapses")
    func openOverlayNeverCollapses() {
        #expect(PanelMachine.shouldCollapse(PanelContext(hasOpenOverlay: true)) == false)
    }

    @Test("a panel with a drag in flight never collapses")
    func draggingNeverCollapses() {
        #expect(PanelMachine.shouldCollapse(PanelContext(isDragging: true)) == false)
    }

    @Test("an idle panel does collapse")
    func idlePanelCollapses() {
        #expect(PanelMachine.shouldCollapse(.idle) == true)
    }

    @Test("pinning survives a full exit-dwell cycle")
    func pinnedSurvivesExitDwell() {
        let pinned = PanelContext(isPinned: true)
        let (state, effects) = PanelMachine.reduce(.expanded, .exitDwellElapsed, pinned)
        #expect(state == .expanded)
        #expect(!effects.contains(.hidePanel))
    }

    @Test("a drag released outside does not take the panel with it")
    func dragInFlightSurvivesExit() {
        let dragging = PanelContext(isDragging: true)
        let (state, _) = PanelMachine.reduce(.expanded, .cursorLeftPanel, dragging)
        #expect(state == .expanded)
    }

    @Test("a focused editor with no keystrokes at all collapses")
    func focusedEditorWithNoKeystrokesCollapses() {
        // Clicking into a note and walking away without typing must not pin the
        // panel open. `firstResponder` never clears on its own, so treating this
        // as "in use" kept the panel open until the app quit.
        let context = PanelContext(isEditorFocused: true, msSinceLastKeystroke: nil)
        #expect(PanelMachine.shouldCollapse(context) == true)
    }

    @Test("a focused editor collapses once idle past its own grace period")
    func focusedEditorCollapsesOnceIdlePastItsGrace() {
        // A minute since the last keystroke: focused or not, the user is done.
        let context = PanelContext(isEditorFocused: true, msSinceLastKeystroke: 60_000)
        #expect(PanelMachine.shouldCollapse(context) == true)
    }

    @Test("a focused editor typed in a moment ago does not collapse")
    func focusedEditorRecentlyTypedDoesNotCollapse() {
        let context = PanelContext(isEditorFocused: true, msSinceLastKeystroke: 500)
        #expect(PanelMachine.shouldCollapse(context) == false)
    }

    @Test("focus earns a longer reprieve than a bare keystroke does")
    func focusOutlastsTypingGraceButNotForever() {
        let past = Int(PanelTiming.typingGrace * 1000) + 500
        #expect(Double(past) / 1000 < PanelTiming.focusedIdleGrace)
        // Beyond typingGrace, so an unfocused editor would collapse here...
        #expect(PanelMachine.shouldCollapse(
            PanelContext(isEditorFocused: false, msSinceLastKeystroke: past)) == true)
        // ...but a focused one is still within focusedIdleGrace.
        #expect(PanelMachine.shouldCollapse(
            PanelContext(isEditorFocused: true, msSinceLastKeystroke: past)) == false)
    }

    @Test("an unfocused editor typed in 500ms ago does not collapse")
    func unfocusedRecentKeystrokeDoesNotCollapse() {
        let context = PanelContext(isEditorFocused: false, msSinceLastKeystroke: 500)
        #expect(PanelMachine.shouldCollapse(context) == false)
    }

    @Test("an unfocused editor last typed in 5s ago does collapse")
    func unfocusedStaleKeystrokeCollapses() {
        let context = PanelContext(isEditorFocused: false, msSinceLastKeystroke: 5_000)
        #expect(PanelMachine.shouldCollapse(context) == true)
    }

    @Test("isWindowKey alone does not suppress collapse")
    func windowKeyAloneDoesNotSuppress() {
        let context = PanelContext(isWindowKey: true)
        #expect(PanelMachine.shouldCollapse(context) == true)
    }

    @Test("an editor being typed in survives a full exit-dwell cycle")
    func focusedEditorSurvivesExitDwell() {
        // A recent keystroke is what makes this "in use". Focus with no typing
        // behind it no longer holds the panel open — see focusedIdleGrace.
        let context = PanelContext(isEditorFocused: true, msSinceLastKeystroke: 200)
        let (state, effects) = PanelMachine.reduce(.expanded, .exitDwellElapsed, context)
        #expect(state == .expanded)
        #expect(!effects.contains(.hidePanel))
    }
}
