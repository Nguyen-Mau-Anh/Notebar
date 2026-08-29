import Foundation
import Testing
@testable import NotebarCore

@Suite("PanelTiming invariants")
struct PanelTimingTests {

    @Test("the trigger strip is exactly as wide as the visible handle")
    func triggerMatchesHandle() {
        // The handle IS the target. When these drift, the user sees a 30pt
        // affordance and has to hit something narrower behind it — the exact
        // defect this equality was introduced to close.
        #expect(PanelTiming.triggerWidth == PanelTiming.handleWidth)
    }

    @Test("maximized width crosses the Tasks board's kanban breakpoint on an ordinary screen")
    func maximizedWidthReachesBoardBreakpoint() {
        // Pins the relationship that makes the side-by-side kanban layout
        // (spec §6.3) reachable at all: at the default 340pt panelWidth it
        // never crosses 700pt, so only the maximized geometry can trigger it.
        // A future change to `maximizedWidthFraction` that silently un-reaches
        // 700pt on a normal display should fail this test.
        let ordinaryScreenWidth: CGFloat = 1800
        let maximizedWidth = ordinaryScreenWidth * PanelTiming.maximizedWidthFraction
        let boardBreakpoint: CGFloat = 700
        #expect(maximizedWidth > boardBreakpoint)
    }
}
