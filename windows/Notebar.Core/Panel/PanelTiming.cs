namespace Notebar.Core.Panel;

/// <summary>
/// Timing and geometry defaults. Every value here is either a user setting or
/// a measurement the layout depends on; nothing may inline these numbers at a
/// call site.
/// </summary>
/// <remarks>
/// Seconds for durations, device-independent pixels for lengths. The panel
/// window works in physical pixels, so <see cref="Notebar.App"/>'s
/// PanelGeometry scales these by the target monitor's DPI — these constants
/// are never used as physical pixels directly.
/// </remarks>
public static class PanelTiming
{
    /// <summary>Cursor must rest in the trigger zone this long before expanding.
    /// Prevents accidental opens when reaching for a scrollbar.</summary>
    public const double EdgeDwell = 0.120;

    /// <summary>Cursor must stay outside the panel this long before collapsing.</summary>
    public const double ExitDwell = 0.350;

    /// <summary>The collapsed handle's size. It lives here rather than with the
    /// design tokens because <see cref="TriggerWidth"/> must equal it — the
    /// handle *is* the target, and two modules disagreeing about its width is
    /// exactly how the affordance stopped working on macOS.</summary>
    public const double HandleWidth = 30;
    public const double HandleHeight = 56;

    /// <summary>The expanded panel's fixed width, flush to the right edge.</summary>
    public const double PanelWidth = 340;

    /// <summary>Fraction of the work area's height the expanded panel occupies,
    /// vertically centred — a card, not a full-height column.</summary>
    public const double PanelHeightFraction = 0.70;

    /// <summary>Fraction of the work area's width the panel occupies when
    /// maximized. At that width it fills the full work-area height instead of
    /// <see cref="PanelHeightFraction"/> — maximized reads as a docked
    /// half-screen column, not a bigger card.</summary>
    public const double MaximizedWidthFraction = 0.5;

    /// <summary>Width of the activation strip at the screen edge. Equal to the
    /// handle width so that hovering the handle — the only thing the user can
    /// see — arms the panel. <see cref="EdgeDwell"/> remains the guard against
    /// accidental opens, not a narrow target.</summary>
    public const double TriggerWidth = HandleWidth;

    /// <summary>Distance from the edge at which polling speeds up.</summary>
    public const double ProximityWidth = 80;

    /// <summary>Cursor must clear the panel bounds by this margin before the
    /// exit timer starts.</summary>
    public const double ExitSlop = 24;

    public const double ExpandDuration = 0.180;

    /// <summary>Deliberately faster than expanding — reads as responsive,
    /// not sluggish.</summary>
    public const double CollapseDuration = 0.140;

    /// <summary>How long after the last keystroke the panel still counts as
    /// "in use". Referenced by PanelMachine.ShouldCollapse.</summary>
    public const double TypingGrace = 2.0;

    // Activation settings ranges. Used both as the slider bounds in Settings
    // and as the clamp the app-state repository applies on read, so a
    // hand-edited database cannot push the panel further than the UI ever
    // could.

    /// <summary>Zero is left in: an open delay of zero is merely eager,
    /// not hostile.</summary>
    public const double EdgeDwellMin = 0.0;
    public const double EdgeDwellMax = 0.5;

    /// <summary>The floor is deliberately above zero — an exit dwell of 0
    /// makes the panel collapse the instant the cursor leaves, which is the
    /// hostile behaviour the suppression rules exist to prevent.</summary>
    public const double ExitDwellMin = 0.05;
    public const double ExitDwellMax = 2.0;

    public const double ExitSlopMin = 0.0;
    public const double ExitSlopMax = 100.0;

    /// <summary>Clamps <paramref name="value"/> into [min, max]. Used by the
    /// app-state repository on every read of a stored timing.</summary>
    public static double Clamp(double value, double min, double max) =>
        value < min ? min : value > max ? max : value;
}
