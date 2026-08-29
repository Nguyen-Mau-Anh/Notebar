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

    @Test("the exit slop widens the panel bounds")
    func exitSlopWidensBounds() {
        let panel = CGRect(x: 1500, y: 0, width: 420, height: 1080)
        // 10pt outside the panel, inside a 24pt slop: still counts as in.
        #expect(EdgeZone.isOutside(cursor: CGPoint(x: 1490, y: 500), panelFrame: panel, slop: 24) == false)
        // 30pt outside: genuinely gone.
        #expect(EdgeZone.isOutside(cursor: CGPoint(x: 1470, y: 500), panelFrame: panel, slop: 24) == true)
    }
}
