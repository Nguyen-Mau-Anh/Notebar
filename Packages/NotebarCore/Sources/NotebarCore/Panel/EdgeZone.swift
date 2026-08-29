import Foundation
import CoreGraphics

public enum EdgeProximity: Equatable, Sendable {
    /// Far from the edge. Poll slowly.
    case away
    /// Close enough to be approaching. Poll fast, but do not arm the dwell.
    case near
    /// Inside the activation strip. Arm the dwell timer.
    case inside
}

/// Classifies a cursor position against a screen's right edge.
///
/// All coordinates are Cocoa screen coordinates: origin bottom-left of the
/// main display, y increasing upward. `NSEvent.mouseLocation` and
/// `NSScreen.frame` both use this space, so no flipping is needed — which is
/// the opposite of most other macOS coordinate work and a classic trap.
public struct EdgeZone: Equatable, Sendable {
    public let triggerWidth: CGFloat
    public let proximityWidth: CGFloat

    public init(triggerWidth: CGFloat, proximityWidth: CGFloat) {
        self.triggerWidth = triggerWidth
        self.proximityWidth = proximityWidth
    }

    public func classify(cursor: CGPoint, screen: CGRect) -> EdgeProximity {
        guard cursor.y >= screen.minY, cursor.y <= screen.maxY else { return .away }

        let distance = screen.maxX - cursor.x

        // Negative means the cursor is past this screen's right edge, which
        // happens when a second display sits to the right. It has left.
        guard distance >= 0 else { return .away }

        if distance <= triggerWidth { return .inside }
        if distance <= proximityWidth { return .near }
        return .away
    }

    /// Whether the cursor has cleared the panel by more than `slop`.
    ///
    /// The slop is what stops the panel collapsing when the cursor drifts a few
    /// points past its edge on the way to a scrollbar (spec section 4.3).
    public static func isOutside(cursor: CGPoint, panelFrame: CGRect, slop: CGFloat) -> Bool {
        !panelFrame.insetBy(dx: -slop, dy: -slop).contains(cursor)
    }
}
