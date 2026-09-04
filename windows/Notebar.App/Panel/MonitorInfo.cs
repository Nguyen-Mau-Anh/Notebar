using Notebar.App.Interop;
using Notebar.Core.Geometry;

namespace Notebar.App.Panel;

/// <summary>Work areas and DPI scales, per monitor.</summary>
/// <remarks>
/// The work area, not the monitor rect: the panel must never sit under the
/// taskbar, wherever the user docked it. Scale comes back from the same call that
/// produced the rect, because fetching them separately is how they end up
/// describing two different monitors on a mixed-DPI setup.
/// </remarks>
internal static class MonitorInfo
{
    /// <summary>The work area containing <paramref name="physicalPoint"/>, in
    /// physical pixels, with that monitor's scale factor.</summary>
    internal static PanelRect WorkAreaContaining(PanelPoint physicalPoint, out double scale)
    {
        var pt = new NativeMethods.POINT
        {
            X = (int)Math.Round(physicalPoint.X),
            Y = (int)Math.Round(physicalPoint.Y),
        };
        IntPtr monitor = NativeMethods.MonitorFromPoint(pt, NativeMethods.MONITOR_DEFAULTTONEAREST);
        return WorkAreaOf(monitor, out scale);
    }

    /// <summary>The primary monitor's work area and scale, used as a fallback
    /// when the cursor position is unavailable.</summary>
    internal static PanelRect PrimaryWorkArea(out double scale) =>
        WorkAreaContaining(new PanelPoint(0, 0), out scale);

    internal static PanelRect WorkAreaOf(IntPtr monitor, out double scale)
    {
        var info = new NativeMethods.MONITORINFO
        {
            cbSize = System.Runtime.InteropServices.Marshal.SizeOf<NativeMethods.MONITORINFO>(),
        };
        if (!NativeMethods.GetMonitorInfo(monitor, ref info))
        {
            scale = 1.0;
            return new PanelRect(0, 0, 1920, 1080);
        }

        scale = NativeMethods.GetDpiForMonitor(monitor, 0, out uint dpiX, out _) == 0
            ? dpiX / 96.0
            : 1.0;

        var w = info.rcWork;
        return new PanelRect(w.Left, w.Top, w.Right - w.Left, w.Bottom - w.Top);
    }

    /// <summary>One line describing the cursor's monitor, plain text, for
    /// diagnostics. Never anything but geometry. This is the cursor's monitor
    /// only, not every display — enumerating all of them needs
    /// EnumDisplayMonitors, which nothing here calls.</summary>
    internal static IReadOnlyList<string> DescribeCursorMonitor()
    {
        // Enumerating every monitor needs EnumDisplayMonitors; the cursor's
        // monitor is what actually matters for a bug report about the panel,
        // so report that one plus the primary.
        var lines = new List<string>();
        if (NativeMethods.GetCursorPos(out var cursor))
        {
            var area = WorkAreaContaining(new PanelPoint(cursor.X, cursor.Y), out double scale);
            lines.Add($"{area.Width}x{area.Height} work area @ ({area.X}, {area.Y}), scale {scale:0.##} (cursor)");
        }
        return lines;
    }
}
