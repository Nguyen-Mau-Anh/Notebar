using Notebar.Core.Geometry;
using Notebar.Core.Panel;
using Xunit;

namespace Notebar.Core.Tests;

/// <summary>
/// Ported verbatim from the macOS EdgeZoneTests, numbers included.
///
/// Windows screen coordinates are top-left origin with Y increasing downward,
/// the opposite of Cocoa — and none of these assertions changes because of it.
/// Every expression in EdgeZone is written against a rect's min and max on each
/// axis, and both coordinate systems have MinY..MaxY spanning the screen. Only
/// the *meaning* of MinY changes, from "bottom" to "top". No arithmetic does.
/// If you came here to flip a sign, that is why you should not.
/// </summary>
public class EdgeZoneTests
{
    // A 1920x1080 screen at the origin. Windows coordinates are top-left
    // origin, Y down; Cocoa's are bottom-left, Y up. The numbers are identical
    // anyway — see the class comment.
    private static readonly EdgeZone Zone = new(triggerWidth: 2, proximityWidth: 80);
    private static readonly PanelRect Screen = new(0, 0, 1920, 1080);

    [Fact]
    public void FarLeftIsAway() =>
        Assert.Equal(EdgeProximity.Away, Zone.Classify(new PanelPoint(10, 500), Screen));

    [Fact]
    public void FortyPointsIsNear() =>
        Assert.Equal(EdgeProximity.Near, Zone.Classify(new PanelPoint(1880, 500), Screen));

    [Fact]
    public void OnePointIsInside() =>
        Assert.Equal(EdgeProximity.Inside, Zone.Classify(new PanelPoint(1919, 500), Screen));

    [Fact]
    public void BoundariesAreInclusive()
    {
        // Exactly triggerWidth from the edge is still inside.
        Assert.Equal(EdgeProximity.Inside, Zone.Classify(new PanelPoint(1918, 500), Screen));
        // Exactly proximityWidth from the edge is still near.
        Assert.Equal(EdgeProximity.Near, Zone.Classify(new PanelPoint(1840, 500), Screen));
        // One point beyond proximityWidth is away.
        Assert.Equal(EdgeProximity.Away, Zone.Classify(new PanelPoint(1839, 500), Screen));
    }

    [Fact]
    public void OutsideVerticalBoundsIsAway()
    {
        Assert.Equal(EdgeProximity.Away, Zone.Classify(new PanelPoint(1919, 2000), Screen));
        Assert.Equal(EdgeProximity.Away, Zone.Classify(new PanelPoint(1919, -10), Screen));
    }

    /// A second display sitting to the right puts the cursor past this screen's
    /// right edge. Negative distance means it has left, not that it is deeply inside.
    [Fact]
    public void PastTheEdgeIsAway() =>
        Assert.Equal(EdgeProximity.Away, Zone.Classify(new PanelPoint(1930, 500), Screen));

    [Fact]
    public void NonZeroOriginScreen()
    {
        var right = new PanelRect(1920, 0, 1920, 1080);
        Assert.Equal(EdgeProximity.Inside, Zone.Classify(new PanelPoint(3839, 500), right));
        Assert.Equal(EdgeProximity.Away, Zone.Classify(new PanelPoint(1930, 500), right));
    }

    /// The handle is the target, so a zone built from PanelTiming must arm on it.
    [Fact]
    public void HandleWidthArmsTrigger()
    {
        var zone = new EdgeZone(PanelTiming.TriggerWidth, PanelTiming.ProximityWidth);
        double justInsideHandle = Screen.MaxX - PanelTiming.HandleWidth + 1;
        Assert.Equal(EdgeProximity.Inside, zone.Classify(new PanelPoint(justInsideHandle, 500), Screen));
    }

    /// The collapsed handle's rect is passed as `screen` — that is what
    /// PanelController.triggerBand does, so that hovering arms the panel only
    /// across the handle's 56pt height, not the whole screen edge. The width
    /// difference does not matter to Classify (only MaxX is read, and both
    /// rects share a right edge); the narrower vertical band is the point.
    [Fact]
    public void HandleSizedRectArmsOnlyItsBand()
    {
        var zone = new EdgeZone(PanelTiming.TriggerWidth, PanelTiming.ProximityWidth);
        var handle = new PanelRect(
            Screen.MaxX - PanelTiming.HandleWidth, 500,
            PanelTiming.HandleWidth, PanelTiming.HandleHeight);

        var inHandle = new PanelPoint(handle.MaxX - 1, handle.MidY);
        Assert.Equal(EdgeProximity.Inside, zone.Classify(inHandle, handle));

        // Both directions, because which one is "above" swaps between Cocoa and
        // Win32 and this is the one test in the file where that actually matters.
        Assert.Equal(EdgeProximity.Away,
            zone.Classify(new PanelPoint(handle.MaxX - 1, handle.MaxY + 50), handle));
        Assert.Equal(EdgeProximity.Away,
            zone.Classify(new PanelPoint(handle.MaxX - 1, handle.MinY - 50), handle));
    }

    /// The slop is what stops the panel collapsing when the cursor drifts a few
    /// points past its edge on the way to a scrollbar.
    [Fact]
    public void ExitSlopWidensBounds()
    {
        var panel = new PanelRect(1500, 0, 420, 1080);
        Assert.False(EdgeZone.IsOutside(new PanelPoint(1490, 500), panel, slop: 24));
        Assert.True(EdgeZone.IsOutside(new PanelPoint(1470, 500), panel, slop: 24));
        Assert.False(EdgeZone.IsOutside(new PanelPoint(1600, 500), panel, slop: 0));
    }
}
