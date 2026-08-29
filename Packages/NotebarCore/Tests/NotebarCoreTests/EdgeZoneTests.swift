import Testing
import Foundation
@testable import NotebarCore

@Suite("EdgeZone geometry")
struct EdgeZoneTests {

    // A 1920x1080 screen whose origin is at zero, in Cocoa coordinates
    // (origin bottom-left, y increasing upward).
    let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    let zone = EdgeZone(triggerWidth: 2, proximityWidth: 80)

    @Test("a cursor on the far left is away")
    func farLeftIsAway() {
        #expect(zone.classify(cursor: CGPoint(x: 10, y: 500), screen: screen) == .away)
    }

    @Test("a cursor 40pt from the right edge is near")
    func fortyPointsIsNear() {
        #expect(zone.classify(cursor: CGPoint(x: 1880, y: 500), screen: screen) == .near)
    }

    @Test("a cursor 1pt from the right edge is inside the trigger")
    func onePointIsInside() {
        #expect(zone.classify(cursor: CGPoint(x: 1919, y: 500), screen: screen) == .inside)
    }

    @Test("the boundary values are inclusive")
    func boundariesAreInclusive() {
        #expect(zone.classify(cursor: CGPoint(x: 1918, y: 500), screen: screen) == .inside)
        #expect(zone.classify(cursor: CGPoint(x: 1840, y: 500), screen: screen) == .near)
        #expect(zone.classify(cursor: CGPoint(x: 1839, y: 500), screen: screen) == .away)
    }

    @Test("a cursor above or below the screen is away")
    func outsideVerticalBoundsIsAway() {
        #expect(zone.classify(cursor: CGPoint(x: 1919, y: 2000), screen: screen) == .away)
        #expect(zone.classify(cursor: CGPoint(x: 1919, y: -10), screen: screen) == .away)
    }

    @Test("a cursor past the right edge is away, not inside")
    func pastTheEdgeIsAway() {
        // This happens with a second display to the right. The cursor has left
        // this screen entirely and must not keep the trigger armed.
        #expect(zone.classify(cursor: CGPoint(x: 1930, y: 500), screen: screen) == .away)
    }

    @Test("a non-zero screen origin is handled")
    func nonZeroOriginScreen() {
        // A second display placed to the right of the main one.
        let right = CGRect(x: 1920, y: 0, width: 1920, height: 1080)
        #expect(zone.classify(cursor: CGPoint(x: 3839, y: 500), screen: right) == .inside)
        #expect(zone.classify(cursor: CGPoint(x: 1930, y: 500), screen: right) == .away)
    }

    @Test("a cursor anywhere within the handle's width arms the trigger")
    func handleWidthArmsTrigger() {
        // The suite's `zone` above uses a literal `triggerWidth: 2` as a unit
        // fixture, which never exercises the 30pt value that actually ships.
        // This builds the zone from `PanelTiming` directly so a drift between
        // the two is caught here, not just by `PanelTimingTests`.
        let shippingZone = EdgeZone(triggerWidth: PanelTiming.triggerWidth, proximityWidth: PanelTiming.proximityWidth)
        // 1pt inside the handle's inner edge.
        let justInsideHandle = CGPoint(x: screen.maxX - PanelTiming.handleWidth + 1, y: 500)
        #expect(shippingZone.classify(cursor: justInsideHandle, screen: screen) == .inside)
    }

    @Test("a handle-sized trigger rect only arms within the handle's height")
    func handleSizedRectArmsOnlyItsBand() {
        // `PanelController.triggerBand` now passes the 30x56 collapsed handle
        // frame, not the full 340x745 panel frame, as `classify`'s `screen`
        // argument. The width difference doesn't matter to `classify` — only
        // `maxX` is used, and both frames share the same right edge — but the
        // narrower vertical band is exactly the point of the change.
        let shippingZone = EdgeZone(triggerWidth: PanelTiming.triggerWidth, proximityWidth: PanelTiming.proximityWidth)
        let handle = CGRect(x: screen.maxX - PanelTiming.handleWidth, y: 500, width: PanelTiming.handleWidth, height: PanelTiming.handleHeight)
        let inHandle = CGPoint(x: handle.maxX - 1, y: handle.midY)
        let aboveHandle = CGPoint(x: handle.maxX - 1, y: handle.maxY + 50)
        #expect(shippingZone.classify(cursor: inHandle, screen: handle) == .inside)
        #expect(shippingZone.classify(cursor: aboveHandle, screen: handle) == .away)
    }

    @Test("the exit slop widens the panel bounds")
    func exitSlopWidensBounds() {
        let panel = CGRect(x: 1500, y: 0, width: 420, height: 1080)
        // 10pt outside the panel, inside a 24pt slop: still counts as in.
        #expect(EdgeZone.isOutside(cursor: CGPoint(x: 1490, y: 500), panelFrame: panel, slop: 24) == false)
        // 30pt outside: genuinely gone.
        #expect(EdgeZone.isOutside(cursor: CGPoint(x: 1470, y: 500), panelFrame: panel, slop: 24) == true)
    }
}
