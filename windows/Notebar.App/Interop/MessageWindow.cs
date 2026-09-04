using System.Runtime.InteropServices;

namespace Notebar.App.Interop;

/// <summary>One hidden top-level window, serving both WM_HOTKEY and the tray
/// icon's callback.</summary>
/// <remarks>
/// RegisterHotKey needs a window whose thread pumps messages, and
/// Shell_NotifyIcon needs a window to send its callback to — one window
/// answers both and avoids a second dependency.
///
/// Deliberately an ordinary window (WS_POPUP, never WS_VISIBLE, WS_EX_TOOLWINDOW,
/// null parent) rather than HWND_MESSAGE: a message-only window sits outside the
/// normal top-level Z-order, which makes SetForegroundWindow on it unreliable —
/// the tray menu's outside-click dismissal depends on that call succeeding — and,
/// worse, a message-only window never receives broadcast messages at all. Explorer
/// restarting (crash or update) destroys every process's tray icon and broadcasts
/// TaskbarCreated so each app can re-add its own; missing that broadcast would
/// mean the icon never comes back. This window stays invisible and out of the
/// taskbar/Alt-Tab exactly as a message-only window would, while remaining
/// eligible for foreground and able to receive broadcasts.
/// </remarks>
internal sealed class MessageWindow : IDisposable
{
    private const string ClassName = "NotebarMessageWindow";

    // Registered once per process; the same message id across every app that
    // asks for it. Checked against 0 (registration failure) before use so a
    // failed registration can't accidentally match every unhandled message.
    private static readonly uint TaskbarCreatedMessage =
        NativeMethods.RegisterWindowMessage("TaskbarCreated");

    // Held in a field, never inlined at the call site: Win32 keeps a raw
    // function pointer to this and the GC has no idea. A collected delegate
    // crashes the process at a time unrelated to anything nearby.
    private readonly NativeMethods.WndProc _wndProc;
    private readonly IntPtr _hInstance;
    private bool _classRegistered;
    private bool _disposed;

    internal IntPtr Handle { get; }

    internal event Action<int>? HotKeyPressed;
    internal event Action? TrayLeftClicked;
    internal event Action? TrayRightClicked;

    /// <summary>Explorer restarted and destroyed every tray icon; re-add
    /// ours. With the panel collapsed and the hotkey possibly held by
    /// another app, missing this is how a user loses all access to
    /// Notebar short of Task Manager.</summary>
    internal event Action? TaskbarRecreated;

    internal MessageWindow()
    {
        _wndProc = WndProc;
        _hInstance = NativeMethods.GetModuleHandle(null);

        var wndClass = new NativeMethods.WNDCLASSEX
        {
            cbSize = Marshal.SizeOf<NativeMethods.WNDCLASSEX>(),
            lpfnWndProc = Marshal.GetFunctionPointerForDelegate(_wndProc),
            hInstance = _hInstance,
            lpszClassName = ClassName,
        };

        if (NativeMethods.RegisterClassEx(ref wndClass) == 0)
        {
            throw new InvalidOperationException(
                $"RegisterClassEx failed (error {Marshal.GetLastWin32Error()})");
        }
        _classRegistered = true;

        Handle = NativeMethods.CreateWindowEx(
            (uint)NativeMethods.WS_EX_TOOLWINDOW, ClassName, null, NativeMethods.WS_POPUP,
            0, 0, 0, 0,
            IntPtr.Zero, IntPtr.Zero, _hInstance, IntPtr.Zero);

        if (Handle == IntPtr.Zero)
        {
            NativeMethods.UnregisterClass(ClassName, _hInstance);
            _classRegistered = false;
            throw new InvalidOperationException(
                $"CreateWindowEx failed (error {Marshal.GetLastWin32Error()})");
        }
    }

    private IntPtr WndProc(IntPtr hwnd, uint msg, IntPtr wParam, IntPtr lParam)
    {
        if (TaskbarCreatedMessage != 0 && msg == TaskbarCreatedMessage)
        {
            TaskbarRecreated?.Invoke();
            return IntPtr.Zero;
        }

        switch (msg)
        {
            case NativeMethods.WM_HOTKEY:
                HotKeyPressed?.Invoke((int)wParam);
                return IntPtr.Zero;

            case NativeMethods.WM_TRAYCALLBACK:
                // wParam is the icon id; lParam is the mouse message that
                // triggered the callback (the default, pre-NIM_SETVERSION
                // behaviour, which nothing here upgrades away from).
                switch ((uint)lParam.ToInt64())
                {
                    case NativeMethods.WM_LBUTTONUP:
                        TrayLeftClicked?.Invoke();
                        break;
                    case NativeMethods.WM_RBUTTONUP:
                        TrayRightClicked?.Invoke();
                        break;
                }
                return IntPtr.Zero;
        }

        return NativeMethods.DefWindowProc(hwnd, msg, wParam, lParam);
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;

        if (Handle != IntPtr.Zero)
            NativeMethods.DestroyWindow(Handle);

        if (_classRegistered)
            NativeMethods.UnregisterClass(ClassName, _hInstance);
    }
}
