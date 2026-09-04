using Notebar.Core.Geometry;

namespace Notebar.Core.Panel;

public enum EdgeProximity
{
    /// <summary>Far from the edge. Poll slowly.</summary>
    Away,
    /// <summary>Close enough to be approaching. Poll fast, but do not arm the dwell.</summary>
    Near,
    /// <summary>Inside the activation strip. Arm the dwell timer.</summary>
    Inside,
}

/// <summary>Classifies a cursor position against a screen's right edge.</summary>
/// <remarks>
/// All coordinates are device-independent pixels in Windows screen space:
/// top-left origin, Y increasing downward. The macOS original was written for
/// Cocoa's bottom-left origin and this is a verbatim port with no sign flips,
/// because every expression below is in terms of a rect's min and max on each
/// axis and both systems have MinY..MaxY spanning the screen. Only what MinY
/// *means* changed.
/// </remarks>
public sealed class EdgeZone(double triggerWidth, double proximityWidth)
{
    public double TriggerWidth { get; } = triggerWidth;
    public double ProximityWidth { get; } = proximityWidth;

    public EdgeProximity Classify(PanelPoint cursor, PanelRect screen)
    {
        if (cursor.Y < screen.MinY || cursor.Y > screen.MaxY) return EdgeProximity.Away;

        double distance = screen.MaxX - cursor.X;

        // Negative means the cursor is past this screen's right edge, which
        // happens when a second display sits to the right. It has left.
        if (distance < 0) return EdgeProximity.Away;

        if (distance <= TriggerWidth) return EdgeProximity.Inside;
        if (distance <= ProximityWidth) return EdgeProximity.Near;
        return EdgeProximity.Away;
    }

    /// <summary>Whether the cursor has cleared the panel by more than
    /// <paramref name="slop"/>. The slop is what stops the panel collapsing when
    /// the cursor drifts a few points past its edge on the way to a scrollbar.</summary>
    public static bool IsOutside(PanelPoint cursor, PanelRect panel, double slop) =>
        !panel.Inflate(slop, slop).Contains(cursor);
}
