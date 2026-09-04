using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Notebar.App.Interop;
using Notebar.App.Panel;
using Notebar.Core.Geometry;
using Notebar.Core.Panel;

namespace Notebar.App;

public partial class App : Application
{
    private PanelWindow? _window;
    private CursorMonitor? _cursorMonitor;
    private PanelController? _panelController;

    /// <summary>The one PanelController for the app's lifetime. Later tasks —
    /// the note editor reporting keystrokes and focus, the tray icon's toggle,
    /// a drag source setting IsDragging — reach it through here rather than
    /// each holding their own reference.</summary>
    internal PanelController? PanelController => _panelController;

    public App() => InitializeComponent();

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        _window = new PanelWindow();

        var cursor = NativeMethods.GetCursorPos(out var pt)
            ? new PanelPoint(pt.X, pt.Y)
            : new PanelPoint(0, 0);
        var workArea = MonitorInfo.WorkAreaContaining(cursor, out double scale);
        var workAreaDips = new PanelRect(
            workArea.X / scale, workArea.Y / scale,
            workArea.Width / scale, workArea.Height / scale);

        _window.ApplyFrame(PanelGeometry.Collapsed(workAreaDips), scale);
        _window.ShowWithoutActivating();

        // Held for the app's lifetime, not scoped to OnLaunched: the controller
        // owns the panel's whole state machine, and the monitor is the only
        // thing driving it. Neither Activate()s the window — hovering must never
        // steal focus, and PanelWindow.ShowWithoutActivating already handles
        // showing it without doing so.
        var queue = DispatcherQueue.GetForCurrentThread();
        _cursorMonitor = new CursorMonitor(queue);
        _panelController = new PanelController(_window, _cursorMonitor, queue);
        _cursorMonitor.Start();
    }
}
