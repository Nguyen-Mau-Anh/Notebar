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
}
