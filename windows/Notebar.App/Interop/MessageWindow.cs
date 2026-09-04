using System.Runtime.InteropServices;

namespace Notebar.App.Interop;

/// <summary>One hidden HWND_MESSAGE window, serving both WM_HOTKEY and the tray
/// icon's callback.</summary>
/// <remarks>
/// RegisterHotKey needs a window whose thread pumps messages, and
/// Shell_NotifyIcon needs a window to send its callback to — one window
/// answers both and avoids a second dependency. HWND_MESSAGE makes it a
/// message-only window: never visible, never in any window list, never a
/// taskbar or Alt-Tab candidate.
/// </remarks>
internal sealed class MessageWindow : IDisposable
{
    private const string ClassName = "NotebarMessageWindow";

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
            0, ClassName, null, 0, 0, 0, 0, 0,
            NativeMethods.HWND_MESSAGE, IntPtr.Zero, _hInstance, IntPtr.Zero);

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
