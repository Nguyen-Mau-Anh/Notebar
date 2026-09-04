using Notebar.Core.Geometry;

namespace Notebar.Core.Panel;

/// <summary>The panel's three rectangles, and the one place device-independent
/// pixels become physical ones.</summary>
/// <remarks>
/// Every length in PanelTiming is in dips. Every Win32 API — GetCursorPos,
/// SetWindowPos, GetMonitorInfo — is in physical pixels. Mixing them produces a
/// panel that is subtly the wrong size only on a scaled display, which is to say
/// only on someone else's machine. Everything crosses that boundary here and
/// nowhere else.
///
/// All rects are anchored to the *work area* rather than the monitor, so the
/// panel never sits under the taskbar wherever the user has docked it.
/// </remarks>
public static class PanelGeometry
{
    public static PanelRect Collapsed(PanelRect workArea) =>
        RightEdge(workArea, PanelTiming.HandleWidth, PanelTiming.HandleHeight);

    public static PanelRect Expanded(PanelRect workArea) =>
        RightEdge(workArea,
                  PanelTiming.PanelWidth,
                  workArea.Height * PanelTiming.PanelHeightFraction);

    /// <summary>Half the work area's width at its full height — a docked column,
    /// not a bigger card.</summary>
    public static PanelRect Maximized(PanelRect workArea) =>
        RightEdge(workArea,
                  workArea.Width * PanelTiming.MaximizedWidthFraction,
                  workArea.Height);

    /// <summary>Flush to the right edge, vertically centred, clamped to fit.</summary>
    private static PanelRect RightEdge(PanelRect workArea, double width, double height)
    {
        double w = Math.Min(width, workArea.Width);
        double h = Math.Min(height, workArea.Height);
        double x = workArea.MaxX - w;
        double y = workArea.MinY + (workArea.Height - h) / 2;
        return new PanelRect(x, y, w, h);
    }

    public static PanelRect ToPhysical(PanelRect dips, double scale) =>
        new(dips.X * scale, dips.Y * scale, dips.Width * scale, dips.Height * scale);

    public static PanelPoint ToDips(PanelPoint physical, double scale) =>
        new(physical.X / scale, physical.Y / scale);
}
