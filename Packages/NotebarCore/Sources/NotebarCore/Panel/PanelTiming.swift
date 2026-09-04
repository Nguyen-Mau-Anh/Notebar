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

    /// The expanded panel's fixed width (spec §4.1). Flush to the right
    /// screen edge.
    public static let panelWidth: CGFloat = 340

    /// Fraction of the screen's visible height the expanded panel occupies,
    /// vertically centred (spec §4.1) — a card, not a full-height column.
    public static let panelHeightFraction: CGFloat = 0.70

    /// Fraction of `visibleFrame.width` the panel occupies when maximized
    /// (spec §6.1). At that width it fills the full screen height instead of
    /// `panelHeightFraction` — maximized reads as a docked half-screen
    /// column, not a bigger card.
    public static let maximizedWidthFraction: CGFloat = 0.5

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

    /// How long a *focused* editor keeps the panel open after the last
    /// keystroke. Longer than `typingGrace` because losing your place
    /// mid-thought is worse than a few extra seconds of panel — but finite,
    /// unlike the original design, which treated focus as absolute. That was
    /// wrong twice over: `firstResponder` is per-window and does not clear
    /// when the user looks away or the app deactivates, so a note clicked once
    /// held the panel open until the app quit. The cursor having already left
    /// the panel is itself decent evidence the user is done; to keep it open
    /// indefinitely, pin it.
    public static let focusedIdleGrace: TimeInterval = 10.0

    /// How long after the last keystroke the panel still counts as "in use".
    /// Referenced by `PanelMachine.shouldCollapse`.
    public static let typingGrace: TimeInterval = 2.0

    // MARK: - Activation settings (spec §6.5)

    /// Sane bounds for `edgeDwell` when it becomes a user setting. Used both
    /// as the slider's range in Settings and as the clamp `AppStateRepository`
    /// applies to a stored value on read, so a hand-edited database can't
    /// push it further than the UI ever could. Zero is left in: an open
    /// delay of zero is merely eager, not hostile.
    public static let edgeDwellRange: ClosedRange<TimeInterval> = 0...0.5

    /// Sane bounds for `exitDwell`. The floor is deliberately above zero —
    /// an `exitDwell` of 0 makes the panel collapse the instant the cursor
    /// leaves, which is the hostile behaviour spec §4.4 exists to prevent —
    /// and the ceiling keeps a stored value from making the panel look stuck
    /// open.
    public static let exitDwellRange: ClosedRange<TimeInterval> = 0.05...2.0

    /// Sane bounds for `exitSlop`.
    public static let exitSlopRange: ClosedRange<CGFloat> = 0...100
}
