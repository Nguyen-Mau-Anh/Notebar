using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Notebar.App.Features;
using Notebar.App.Interop;
using Notebar.App.Panel;
using Notebar.Core.Geometry;
using Notebar.Core.Models;
using Notebar.Core.Repositories;

namespace Notebar.App;

public sealed partial class PanelWindow : Window
{
    private readonly IntPtr _hwnd;
    private readonly AppWindow _appWindow;

    public PanelWindow()
    {
        InitializeComponent();
        Title = "Notebar";

        _hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
        _appWindow = AppWindow.GetFromWindowId(
            Microsoft.UI.Win32Interop.GetWindowIdFromWindow(_hwnd));

        if (_appWindow.Presenter is OverlappedPresenter presenter)
        {
            presenter.SetBorderAndTitleBar(false, false);
            presenter.IsResizable = false;
            presenter.IsMinimizable = false;
            presenter.IsMaximizable = false;
            presenter.IsAlwaysOnTop = true;
        }

        // A tool window: no taskbar button, no Alt-Tab entry. The panel is an
        // overlay, not a place the window manager should send the user.
        _appWindow.IsShownInSwitchers = false;
        var ex = NativeMethods.GetWindowLongPtr(_hwnd, NativeMethods.GWL_EXSTYLE);
        NativeMethods.SetWindowLongPtr(_hwnd, NativeMethods.GWL_EXSTYLE,
            ex | NativeMethods.WS_EX_TOOLWINDOW);
    }

    internal IntPtr Handle => _hwnd;

    /// <summary>Hands the page its PanelController seam, plus the repositories Task 12's
    /// Notes tab, Task 14's Tasks tab, Task 15's linking, and Task 16's Settings tab need to
    /// construct themselves. Called once from App.xaml.cs after PanelController exists --
    /// the controller wraps this window, so it cannot exist before this constructor has
    /// already run and RootPage has already been built by InitializeComponent above.</summary>
    internal void AttachController(
        PanelController panelController,
        INoteRepository noteRepository,
        IOpenTabRepository openTabRepository,
        IAttachmentRepository attachmentRepository,
        ITaskRepository taskRepository,
        ILinkRepository linkRepository,
        IAppStateRepository appStateRepository,
        IDiagnosticsRepository diagnosticsRepository) =>
        Root.AttachController(panelController, noteRepository, openTabRepository, attachmentRepository, taskRepository, linkRepository, appStateRepository, diagnosticsRepository);

    /// <summary>Forwards to RootPage.ApplyTheme -- see its own remarks. App.xaml.cs calls
    /// this once at launch with the persisted theme, before AttachController even runs
    /// (RequestedTheme can be set on a FrameworkElement regardless of whether the panel is
    /// visible yet), and SettingsTabControl calls it again on every live change.</summary>
    internal void ApplyTheme(Theme theme) => Root.ApplyTheme(theme);

    /// <summary>Switches the rail's own selection to Settings. Called by App.ShowSettings,
    /// the tray menu's "Settings" entry -- the same entry point macOS's own Settings menu
    /// item goes through -- so choosing it always lands on the Settings tab rather than
    /// whatever tab happened to be active when the panel was last collapsed.</summary>
    internal void ShowSettingsTab() => Root.SelectTab(AppTab.Settings);

    /// <summary>Places the window from a rect in device-independent pixels
    /// relative to the given monitor's work area.</summary>
    internal void ApplyFrame(PanelRect dips, double scale)
    {
        var p = Notebar.Core.Panel.PanelGeometry.ToPhysical(dips, scale);
        NativeMethods.SetWindowPos(
            _hwnd, NativeMethods.HWND_TOPMOST,
            (int)Math.Round(p.X), (int)Math.Round(p.Y),
            (int)Math.Round(p.Width), (int)Math.Round(p.Height),
            NativeMethods.SWP_NOACTIVATE);
    }

    /// <summary>Shows the panel without taking focus from whatever the user is
    /// working in.</summary>
    /// <remarks>
    /// macOS's nonactivating panel can become key without activating the app.
    /// Windows has no equivalent: WS_EX_NOACTIVATE is the closest thing and it
    /// would stop the editor ever receiving keyboard focus, which is a worse
    /// problem than the one it solves. So the panel shows without activating —
    /// hovering never steals focus — while a click still activates it, which is
    /// exactly what someone clicking into an editor wants.
    /// </remarks>
    internal void ShowWithoutActivating() =>
        NativeMethods.ShowWindow(_hwnd, NativeMethods.SW_SHOWNOACTIVATE);

    internal void HideWindow() =>
        NativeMethods.ShowWindow(_hwnd, NativeMethods.SW_HIDE);

    /// <summary>Re-asserts topmost without moving or resizing. Another app going
    /// fullscreen, or the user switching virtual desktops, can knock the panel out
    /// of the topmost band; the cursor monitor calls this on its idle tick, which
    /// costs one call every 100 ms and removes a whole class of "it stopped
    /// appearing" reports.</summary>
    internal void ReassertTopmost() =>
        NativeMethods.SetWindowPos(_hwnd, NativeMethods.HWND_TOPMOST, 0, 0, 0, 0,
            NativeMethods.SWP_NOSIZE | NativeMethods.SWP_NOMOVE | NativeMethods.SWP_NOACTIVATE);
}
