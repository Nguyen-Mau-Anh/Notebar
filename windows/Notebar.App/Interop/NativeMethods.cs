using System.Runtime.InteropServices;

namespace Notebar.App.Interop;

/// <summary>Every P/Invoke the app makes, in one file.</summary>
/// <remarks>
/// Deliberately one file so the app's entire native surface is auditable at a
/// glance. Nothing here requires elevation, a permission prompt, or a hook —
/// SetWindowsHookEx, WH_KEYBOARD_LL, and WH_MOUSE_LL are banned: they are
/// unnecessary for everything this app does, they trip antivirus heuristics, and
/// they are the Windows equivalent of the Accessibility permission this project
/// has always refused. If a future need seems to require one, it does not.
/// </remarks>
internal static partial class NativeMethods
{
    [StructLayout(LayoutKind.Sequential)]
    internal struct POINT { public int X; public int Y; }

    [StructLayout(LayoutKind.Sequential)]
    internal struct RECT { public int Left, Top, Right, Bottom; }

    [StructLayout(LayoutKind.Sequential)]
    internal struct MONITORINFO
    {
        public int cbSize;
        public RECT rcMonitor;
        public RECT rcWork;
        public uint dwFlags;
    }

    // --- cursor ---

    /// <summary>The sanctioned way to read the cursor. No prompt, no elevation —
    /// the direct analogue of NSEvent.mouseLocation on macOS.</summary>
    [LibraryImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static partial bool GetCursorPos(out POINT point);

    // --- monitors ---

    internal const uint MONITOR_DEFAULTTONEAREST = 2;

    [LibraryImport("user32.dll")]
    internal static partial IntPtr MonitorFromPoint(POINT pt, uint flags);

    [LibraryImport("user32.dll")]
    internal static partial IntPtr MonitorFromWindow(IntPtr hwnd, uint flags);

    [LibraryImport("user32.dll", EntryPoint = "GetMonitorInfoW")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static partial bool GetMonitorInfo(IntPtr monitor, ref MONITORINFO info);

    [LibraryImport("user32.dll")]
    internal static partial uint GetDpiForWindow(IntPtr hwnd);

    /// <summary>Per-monitor DPI, for the monitor the cursor is on rather than the
    /// one the window happens to be on. MDT_EFFECTIVE_DPI = 0.</summary>
    [LibraryImport("shcore.dll")]
    internal static partial int GetDpiForMonitor(IntPtr monitor, int dpiType, out uint dpiX, out uint dpiY);

    // --- window placement ---

    internal static readonly IntPtr HWND_TOPMOST = new(-1);

    internal const uint SWP_NOSIZE = 0x0001;
    internal const uint SWP_NOMOVE = 0x0002;
    internal const uint SWP_NOACTIVATE = 0x0010;
    internal const uint SWP_SHOWWINDOW = 0x0040;
    internal const uint SWP_NOZORDER = 0x0004;

    internal const int SW_HIDE = 0;
    internal const int SW_SHOWNOACTIVATE = 4;

    internal const int GWL_EXSTYLE = -20;
    internal const int WS_EX_TOOLWINDOW = 0x00000080;
    internal const int WS_EX_TOPMOST = 0x00000008;

    [LibraryImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static partial bool SetWindowPos(
        IntPtr hwnd, IntPtr insertAfter, int x, int y, int cx, int cy, uint flags);

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static partial bool ShowWindow(IntPtr hwnd, int cmdShow);

    [LibraryImport("user32.dll", EntryPoint = "GetWindowLongPtrW")]
    internal static partial IntPtr GetWindowLongPtr(IntPtr hwnd, int index);

    [LibraryImport("user32.dll", EntryPoint = "SetWindowLongPtrW")]
    internal static partial IntPtr SetWindowLongPtr(IntPtr hwnd, int index, IntPtr value);

    [LibraryImport("user32.dll")]
    internal static partial IntPtr GetForegroundWindow();

    /// <summary>The backstop that clears IsDragging when a drag ends outside
    /// the panel and no drop event ever reaches us. Polls the physical button
    /// state rather than tracking press/release, which is why it works
    /// regardless of what started the drag.</summary>
    [LibraryImport("user32.dll")]
    internal static partial short GetAsyncKeyState(int vKey);

    // --- hotkey ---

    internal const uint MOD_CONTROL = 0x0002;
    internal const uint MOD_SHIFT = 0x0004;
    internal const uint MOD_NOREPEAT = 0x4000;
    internal const int WM_HOTKEY = 0x0312;

    [LibraryImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static partial bool RegisterHotKey(IntPtr hwnd, int id, uint modifiers, uint vk);

    [LibraryImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static partial bool UnregisterHotKey(IntPtr hwnd, int id);
}
