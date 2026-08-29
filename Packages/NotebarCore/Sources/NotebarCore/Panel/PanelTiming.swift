import Foundation

/// Timing defaults from spec section 4.3. Every value here becomes a user
/// setting in M4; nothing may inline these numbers at a call site.
public enum PanelTiming {
    /// Cursor must rest in the trigger zone this long before expanding.
    /// Prevents accidental opens when reaching for a scrollbar.
    public static let edgeDwell: TimeInterval = 0.120

    /// Cursor must stay outside the panel this long before collapsing.
    public static let exitDwell: TimeInterval = 0.350

    /// The collapsed handle's size. It lives here rather than in the app
    /// target's Tokens because `triggerWidth` must equal it — the handle *is*
    /// the target, and two modules disagreeing about its width is exactly how
    /// the affordance stopped working.
    public static let handleWidth: CGFloat = 30
    public static let handleHeight: CGFloat = 56

    /// Width of the activation strip at the screen edge. Equal to the handle
    /// width so that hovering the handle — the only thing the user can see —
    /// arms the panel. The 120 ms `edgeDwell` remains the guard against
    /// accidental opens, not a narrow target.
    public static let triggerWidth: CGFloat = handleWidth

    /// Distance from the edge at which polling speeds up.
    public static let proximityWidth: CGFloat = 80

    /// Cursor must clear the panel bounds by this margin before the exit timer starts.
    public static let exitSlop: CGFloat = 24

    public static let expandDuration: TimeInterval = 0.180

    /// Deliberately faster than expanding — reads as responsive, not sluggish.
    public static let collapseDuration: TimeInterval = 0.140

    /// How long after the last keystroke the panel still counts as "in use".
    /// Referenced by `PanelMachine.shouldCollapse`.
    public static let typingGrace: TimeInterval = 2.0
}
