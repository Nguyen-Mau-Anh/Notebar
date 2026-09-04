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
    private static readonly EdgeZone Zone = new(triggerWidth: 4, proximityWidth: 80);
    private static readonly PanelRect Screen = new(0, 0, 1440, 900);

    [Fact]
    public void FarLeftIsAway() =>
        Assert.Equal(EdgeProximity.Away, Zone.Classify(new PanelPoint(200, 400), Screen));

    [Fact]
    public void FortyPointsIsNear() =>
        Assert.Equal(EdgeProximity.Near, Zone.Classify(new PanelPoint(1400, 400), Screen));

    [Fact]
    public void OnePointIsInside() =>
        Assert.Equal(EdgeProximity.Inside, Zone.Classify(new PanelPoint(1439, 400), Screen));

    [Fact]
    public void BoundariesAreInclusive()
    {
        // Exactly triggerWidth from the edge is still inside.
        Assert.Equal(EdgeProximity.Inside, Zone.Classify(new PanelPoint(1436, 400), Screen));
        // Exactly proximityWidth from the edge is still near.
        Assert.Equal(EdgeProximity.Near, Zone.Classify(new PanelPoint(1360, 400), Screen));
        // One point beyond proximityWidth is away.
        Assert.Equal(EdgeProximity.Away, Zone.Classify(new PanelPoint(1359, 400), Screen));
    }

    [Fact]
    public void OutsideVerticalBoundsIsAway()
    {
        Assert.Equal(EdgeProximity.Away, Zone.Classify(new PanelPoint(1439, -1), Screen));
        Assert.Equal(EdgeProximity.Away, Zone.Classify(new PanelPoint(1439, 901), Screen));
    }

    /// A second display sitting to the right puts the cursor past this screen's
    /// right edge. Negative distance means it has left, not that it is deeply inside.
    [Fact]
    public void PastTheEdgeIsAway() =>
        Assert.Equal(EdgeProximity.Away, Zone.Classify(new PanelPoint(1441, 400), Screen));

    [Fact]
    public void NonZeroOriginScreen()
    {
        var right = new PanelRect(1440, 0, 1280, 800);
        Assert.Equal(EdgeProximity.Inside, Zone.Classify(new PanelPoint(2719, 400), right));
        Assert.Equal(EdgeProximity.Away, Zone.Classify(new PanelPoint(1500, 400), right));
    }

    /// The handle is the target, so a zone built from PanelTiming must arm on it.
    [Fact]
    public void HandleWidthArmsTrigger()
    {
        var zone = new EdgeZone(PanelTiming.TriggerWidth, PanelTiming.ProximityWidth);
        double justInsideHandle = Screen.MaxX - PanelTiming.HandleWidth + 1;
        Assert.Equal(EdgeProximity.Inside, zone.Classify(new PanelPoint(justInsideHandle, 400), Screen));
    }

    /// ...and must not arm on the band beyond it.
    [Fact]
    public void HandleSizedRectArmsOnlyItsBand()
    {
        var zone = new EdgeZone(PanelTiming.TriggerWidth, PanelTiming.ProximityWidth);
        double justOutsideHandle = Screen.MaxX - PanelTiming.HandleWidth - 1;
        Assert.Equal(EdgeProximity.Near, zone.Classify(new PanelPoint(justOutsideHandle, 400), Screen));
    }

    /// The slop is what stops the panel collapsing when the cursor drifts a few
    /// points past its edge on the way to a scrollbar.
    [Fact]
    public void ExitSlopWidensBounds()
    {
        var panel = new PanelRect(1100, 100, 340, 700);
        Assert.False(EdgeZone.IsOutside(new PanelPoint(1090, 400), panel, slop: 24));
        Assert.True(EdgeZone.IsOutside(new PanelPoint(1070, 400), panel, slop: 24));
        Assert.False(EdgeZone.IsOutside(new PanelPoint(1200, 400), panel, slop: 0));
    }
}
