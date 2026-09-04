using Notebar.Core.Geometry;
using Notebar.Core.Panel;
using Xunit;

namespace Notebar.Core.Tests;

public class PanelGeometryTests
{
    /// A 1920x1080 display with a 40dip taskbar at the bottom.
    private static readonly PanelRect WorkArea = new(0, 0, 1920, 1040);

    [Fact]
    public void CollapsedIsTheHandleFlushToTheRightEdge()
    {
        var r = PanelGeometry.Collapsed(WorkArea);
        Assert.Equal(WorkArea.MaxX, r.MaxX);
        Assert.Equal(PanelTiming.HandleWidth, r.Width);
        Assert.Equal(PanelTiming.HandleHeight, r.Height);
    }

    [Fact]
    public void CollapsedIsVerticallyCentred()
    {
        var r = PanelGeometry.Collapsed(WorkArea);
        Assert.Equal(WorkArea.MinY + (WorkArea.Height - r.Height) / 2, r.MinY, precision: 6);
    }

    [Fact]
    public void ExpandedIsTheFixedWidthFlushToTheRightEdge()
    {
        var r = PanelGeometry.Expanded(WorkArea);
        Assert.Equal(WorkArea.MaxX, r.MaxX);
        Assert.Equal(PanelTiming.PanelWidth, r.Width);
    }

    /// A card, not a full-height column.
    [Fact]
    public void ExpandedIsSeventyPercentTallAndCentred()
    {
        var r = PanelGeometry.Expanded(WorkArea);
        Assert.Equal(WorkArea.Height * PanelTiming.PanelHeightFraction, r.Height, precision: 6);
        Assert.Equal(WorkArea.MinY + (WorkArea.Height - r.Height) / 2, r.MinY, precision: 6);
    }

    /// Maximized reads as a docked half-screen column, so it takes the full work
    /// area height rather than the 70% fraction.
    [Fact]
    public void MaximizedIsHalfWideAndFullHeight()
    {
        var r = PanelGeometry.Maximized(WorkArea);
        Assert.Equal(WorkArea.Width * PanelTiming.MaximizedWidthFraction, r.Width, precision: 6);
        Assert.Equal(WorkArea.Height, r.Height, precision: 6);
        Assert.Equal(WorkArea.MaxX, r.MaxX);
        Assert.Equal(WorkArea.MinY, r.MinY);
    }

    /// A work area whose origin is not zero — a second monitor, or a taskbar
    /// docked to the top or left. Everything must be relative to it, never to
    /// zero.
    [Fact]
    public void RespectsANonZeroWorkAreaOrigin()
    {
        var offset = new PanelRect(1920, 60, 1280, 740);
        foreach (var r in new[]
        {
            PanelGeometry.Collapsed(offset),
            PanelGeometry.Expanded(offset),
            PanelGeometry.Maximized(offset),
        })
        {
            Assert.Equal(offset.MaxX, r.MaxX);
            Assert.True(r.MinY >= offset.MinY, "panel must not start above the work area");
            Assert.True(r.MaxY <= offset.MaxY, "panel must not extend below the work area");
        }
    }

    /// A work area shorter than the handle cannot fit it. Clamp rather than
    /// producing a negative-origin rect that Windows will place off-screen.
    [Fact]
    public void ClampsToAWorkAreaSmallerThanThePanel()
    {
        var tiny = new PanelRect(0, 0, 200, 40);
        var r = PanelGeometry.Expanded(tiny);
        Assert.True(r.Width <= tiny.Width);
        Assert.True(r.MinY >= tiny.MinY);
        Assert.True(r.MaxY <= tiny.MaxY);
    }

    /// Windows APIs take physical pixels; PanelTiming is in dips. Every value
    /// crosses this boundary exactly once, here.
    [Fact]
    public void ScalesToPhysicalPixels()
    {
        var dips = new PanelRect(100, 50, 340, 700);
        var physical = PanelGeometry.ToPhysical(dips, scale: 1.5);
        Assert.Equal(150, physical.X);
        Assert.Equal(75, physical.Y);
        Assert.Equal(510, physical.Width);
        Assert.Equal(1050, physical.Height);
    }

    [Fact]
    public void ScalesCursorPositionsBackToDips()
    {
        var p = PanelGeometry.ToDips(new PanelPoint(2880, 1620), scale: 2.0);
        Assert.Equal(1440, p.X);
        Assert.Equal(810, p.Y);
    }

    [Fact]
    public void ScaleOfOneIsTheIdentity()
    {
        var dips = new PanelRect(10, 20, 30, 40);
        Assert.Equal(dips, PanelGeometry.ToPhysical(dips, scale: 1.0));
    }

    /// Windows' common scale factors are 125%, 150% and 175%. Only 1.0, 1.5 and
    /// 2.0 were covered, and a fractional scale is exactly where a rounding or
    /// ordering mistake in the conversion would first show up.
    [Theory]
    [InlineData(1.25)]
    [InlineData(1.75)]
    public void ScalesCorrectlyAtFractionalDpi(double scale)
    {
        var dips = new PanelRect(100, 50, PanelTiming.PanelWidth, 700);
        var physical = PanelGeometry.ToPhysical(dips, scale);

        Assert.Equal(100 * scale, physical.X, precision: 6);
        Assert.Equal(50 * scale, physical.Y, precision: 6);
        Assert.Equal(PanelTiming.PanelWidth * scale, physical.Width, precision: 6);
        Assert.Equal(700 * scale, physical.Height, precision: 6);

        // And back again, losslessly.
        var roundTripped = PanelGeometry.ToDips(new PanelPoint(physical.X, physical.Y), scale);
        Assert.Equal(dips.X, roundTripped.X, precision: 6);
        Assert.Equal(dips.Y, roundTripped.Y, precision: 6);
    }

    /// The boundary where clamping starts to matter: a work area exactly the
    /// size of the panel. Clamping must be a no-op here, not an off-by-one.
    [Fact]
    public void AWorkAreaExactlyThePanelSizeIsNotClamped()
    {
        var exact = new PanelRect(0, 0, PanelTiming.PanelWidth, 1000);
        var r = PanelGeometry.Expanded(exact);

        Assert.Equal(PanelTiming.PanelWidth, r.Width, precision: 6);
        Assert.Equal(exact.MinX, r.MinX, precision: 6);
        Assert.Equal(exact.MaxX, r.MaxX, precision: 6);
    }
}
