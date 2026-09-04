using System.Runtime.InteropServices;
using Notebar.App.Interop;
using Notebar.App.Panel;
using Notebar.Core.Panel;

namespace Notebar.App;

/// <summary>The tray presence: an icon via Shell_NotifyIcon, plus its
/// left-click toggle and right-click menu.</summary>
/// <remarks>
/// The menu bar item on macOS turned out to be hidden by the notch — the
/// reason Settings grew a Quit button there. The Windows tray has the same
/// failure mode with a collapsed overflow, so Quit lives in this menu but is
/// never the only way out: App.Quit is reachable independently of whether
/// the icon is even visible.
/// </remarks>
internal sealed class TrayIcon : IDisposable
{
    private const int IconId = 1;
    private const uint MenuIdShow = 1;
    private const uint MenuIdSettings = 2;
    private const uint MenuIdQuit = 3;

    private readonly MessageWindow _messageWindow;
    private readonly PanelController _panelController;
    private readonly Action _onShowSettings;
    private readonly Action _onQuit;

    private IntPtr _hIcon;
    private bool _hIconOwned;
    private bool _added;
    private bool _disposed;

    internal TrayIcon(
        MessageWindow messageWindow,
        PanelController panelController,
        Action onShowSettings,
        Action onQuit)
    {
        _messageWindow = messageWindow;
        _panelController = panelController;
        _onShowSettings = onShowSettings;
        _onQuit = onQuit;

        _messageWindow.TrayLeftClicked += OnTrayLeftClicked;
        _messageWindow.TrayRightClicked += ShowMenu;
        // Explorer restarting (crash or update) destroys every tray icon;
        // Show() re-runs NIM_ADD to put ours back. See MessageWindow's
        // remarks for why this requires an ordinary hidden window rather
        // than a message-only one.
        _messageWindow.TaskbarRecreated += Show;
    }

    private void OnTrayLeftClicked() => _panelController.Send(PanelEvent.ToggleRequested);

    internal void Show()
    {
        // Show() can run more than once (TaskbarRecreated), so the previous
        // handle must go before it's overwritten rather than leaking a GDI
        // icon handle every time Explorer restarts. Only if it was ours to
        // begin with — the IDI_APPLICATION fallback is a shared system
        // resource, never destroyed by this process.
        if (_hIconOwned && _hIcon != IntPtr.Zero)
        {
            NativeMethods.DestroyIcon(_hIcon);
        }
        _hIcon = LoadAppIcon();

        var data = new NativeMethods.NOTIFYICONDATAW
        {
            cbSize = Marshal.SizeOf<NativeMethods.NOTIFYICONDATAW>(),
            hWnd = _messageWindow.Handle,
            uID = IconId,
            uFlags = NativeMethods.NIF_MESSAGE | NativeMethods.NIF_ICON | NativeMethods.NIF_TIP,
            uCallbackMessage = NativeMethods.WM_TRAYCALLBACK,
            hIcon = _hIcon,
            szTip = "Notebar",
        };

        _added = NativeMethods.Shell_NotifyIcon(NativeMethods.NIM_ADD, ref data);
    }

    internal void ShowMenu()
    {
        IntPtr hMenu = NativeMethods.CreatePopupMenu();
        if (hMenu == IntPtr.Zero) return;

        try
        {
            NativeMethods.AppendMenu(hMenu, NativeMethods.MF_STRING, (UIntPtr)MenuIdShow, "Show Notebar");
            NativeMethods.AppendMenu(hMenu, NativeMethods.MF_STRING, (UIntPtr)MenuIdSettings, "Settings");
            NativeMethods.AppendMenu(hMenu, NativeMethods.MF_SEPARATOR, UIntPtr.Zero, null);
            NativeMethods.AppendMenu(hMenu, NativeMethods.MF_STRING, (UIntPtr)MenuIdQuit, "Quit Notebar");

            NativeMethods.GetCursorPos(out var pt);

            // Without this the popup never gets a dismiss click and stays
            // open when the user clicks elsewhere. Standard TrackPopupMenu
            // incantation (see Microsoft's own sample tray apps):
            // SetForegroundWindow before, a no-op PostMessage after.
            // SetForegroundWindow can fail — Windows restricts which process
            // may steal foreground — and there's nowhere to surface that
            // today, so a failure here is deliberately ignored rather than
            // silently discarded: it only degrades dismiss-on-outside-click,
            // never the menu's own behaviour.
            bool gotForeground = NativeMethods.SetForegroundWindow(_messageWindow.Handle);
            System.Diagnostics.Debug.WriteLineIf(!gotForeground,
                "TrayIcon.ShowMenu: SetForegroundWindow failed; the menu may not auto-dismiss.");

            int selected = NativeMethods.TrackPopupMenu(
                hMenu,
                NativeMethods.TPM_RIGHTBUTTON | NativeMethods.TPM_RETURNCMD,
                pt.X, pt.Y, 0, _messageWindow.Handle, IntPtr.Zero);

            NativeMethods.PostMessage(_messageWindow.Handle, NativeMethods.WM_NULL, IntPtr.Zero, IntPtr.Zero);

            switch ((uint)selected)
            {
                case MenuIdShow:
                    _panelController.Send(PanelEvent.ToggleRequested);
                    break;
                case MenuIdSettings:
                    _onShowSettings();
                    break;
                case MenuIdQuit:
                    _onQuit();
                    break;
            }
        }
        finally
        {
            NativeMethods.DestroyMenu(hMenu);
        }
    }

    /// <summary>The exe's own embedded icon (ApplicationIcon in the csproj
    /// embeds Assets/Notebar.ico at index 0), rather than a loose file — the
    /// portable publish output does not otherwise carry Assets/Notebar.ico as
    /// a standalone file, and the exe already does. Falls back to the system
    /// "application" icon rather than leaving the tray entry blank: the tray
    /// is the primary way to reach this app when the panel is collapsed and
    /// the hotkey is taken by another app, so it always ends up with
    /// something clickable.</summary>
    private IntPtr LoadAppIcon()
    {
        string? exePath = Environment.ProcessPath;
        IntPtr hIcon = string.IsNullOrEmpty(exePath)
            ? IntPtr.Zero
            : NativeMethods.ExtractIcon(IntPtr.Zero, exePath, 0);

        // ExtractIcon returns 1 (not 0) when the file has no icons at all.
        if (hIcon == new IntPtr(1)) hIcon = IntPtr.Zero;

        if (hIcon != IntPtr.Zero)
        {
            // Only an icon ExtractIcon actually produced is ours to destroy.
            _hIconOwned = true;
            return hIcon;
        }

        // IDI_APPLICATION: a shared system resource, never destroyed by this
        // process — see the DestroyIcon guard in Dispose.
        _hIconOwned = false;
        return NativeMethods.LoadIcon(IntPtr.Zero, new IntPtr(32512));
    }

    /// <summary>NIM_DELETE, always, before the process ends: an orphaned tray
    /// icon that outlives its process is a well-known Windows annoyance —
    /// the user has to hover it to make it disappear.</summary>
    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;

        _messageWindow.TrayLeftClicked -= OnTrayLeftClicked;
        _messageWindow.TrayRightClicked -= ShowMenu;
        _messageWindow.TaskbarRecreated -= Show;

        if (_added)
        {
            var data = new NativeMethods.NOTIFYICONDATAW
            {
                cbSize = Marshal.SizeOf<NativeMethods.NOTIFYICONDATAW>(),
                hWnd = _messageWindow.Handle,
                uID = IconId,
            };
            NativeMethods.Shell_NotifyIcon(NativeMethods.NIM_DELETE, ref data);
        }

        if (_hIconOwned && _hIcon != IntPtr.Zero)
            NativeMethods.DestroyIcon(_hIcon);
    }
}
