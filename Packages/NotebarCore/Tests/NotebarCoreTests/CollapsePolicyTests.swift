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

    @Test("a focused editor does not collapse, even with no keystrokes recorded")
    func focusedEditorNeverCollapsesWithNoKeystrokes() {
        let context = PanelContext(isEditorFocused: true, msSinceLastKeystroke: nil)
        #expect(PanelMachine.shouldCollapse(context) == false)
    }

    @Test("a focused editor does not collapse even when the last keystroke is far older than the grace period")
    func focusedEditorNeverCollapsesRegardlessOfKeystrokeAge() {
        let context = PanelContext(isEditorFocused: true, msSinceLastKeystroke: 60_000)
        #expect(PanelMachine.shouldCollapse(context) == false)
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

    @Test("a focused editor survives a full exit-dwell cycle")
    func focusedEditorSurvivesExitDwell() {
        let context = PanelContext(isEditorFocused: true)
        let (state, effects) = PanelMachine.reduce(.expanded, .exitDwellElapsed, context)
        #expect(state == .expanded)
        #expect(!effects.contains(.hidePanel))
    }
}
