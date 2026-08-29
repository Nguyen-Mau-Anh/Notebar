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
}
