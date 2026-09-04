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

    // --- message-only window ---
    //
    // Classic [DllImport], not [LibraryImport], for this whole group: WNDCLASSEX
    // carries a raw function-pointer field and string fields, and NOTIFYICONDATAW
    // (below) carries fixed-size character buffers — none of these are blittable
    // in a way the LibraryImport source generator marshals without per-field
    // attributes it does not support on these struct shapes. The legacy marshaler
    // has handled this exact struct family correctly for 20 years; one marshaling
    // strategy across the whole new tray/hotkey-window surface is less risk than
    // mixing two, especially with no local Windows compiler to iterate against.

    internal static readonly IntPtr HWND_MESSAGE = new(-3);

    internal const uint WM_NULL = 0x0000;
    internal const uint WM_LBUTTONUP = 0x0202;
    internal const uint WM_RBUTTONUP = 0x0205;
    internal const uint WM_APP = 0x8000;

    /// <summary>Shell_NotifyIcon's callback message, sent to the message
    /// window with wParam = icon id and lParam = the originating mouse
    /// message (WM_LBUTTONUP, WM_RBUTTONUP, ...).</summary>
    internal const uint WM_TRAYCALLBACK = WM_APP + 1;

    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    internal delegate IntPtr WndProc(IntPtr hwnd, uint msg, IntPtr wParam, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    internal struct WNDCLASSEX
    {
        public int cbSize;
        public uint style;
        public IntPtr lpfnWndProc;
        public int cbClsExtra;
        public int cbWndExtra;
        public IntPtr hInstance;
        public IntPtr hIcon;
        public IntPtr hCursor;
        public IntPtr hbrBackground;
        public string? lpszMenuName;
        public string lpszClassName = string.Empty;
        public IntPtr hIconSm;
    }

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    internal static extern IntPtr GetModuleHandle(string? lpModuleName);

    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    internal static extern ushort RegisterClassEx(ref WNDCLASSEX lpwcx);

    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool UnregisterClass(string lpClassName, IntPtr hInstance);

    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    internal static extern IntPtr CreateWindowEx(
        uint dwExStyle, string lpClassName, string? lpWindowName, uint dwStyle,
        int x, int y, int nWidth, int nHeight,
        IntPtr hWndParent, IntPtr hMenu, IntPtr hInstance, IntPtr lpParam);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool DestroyWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    internal static extern IntPtr DefWindowProc(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool PostMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);

    // --- tray icon ---

    internal const uint NIM_ADD = 0x0000;
    internal const uint NIM_MODIFY = 0x0001;
    internal const uint NIM_DELETE = 0x0002;

    internal const uint NIF_MESSAGE = 0x0001;
    internal const uint NIF_ICON = 0x0002;
    internal const uint NIF_TIP = 0x0004;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    internal struct NOTIFYICONDATAW
    {
        public int cbSize;
        public IntPtr hWnd;
        public int uID;
        public uint uFlags;
        public uint uCallbackMessage;
        public IntPtr hIcon;
        // Field initializers, not left null: a null string against
        // ByValTStr fails to marshal, and every call site below sets only
        // the fields NIF_* flags actually require.
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string szTip = string.Empty;
        public int dwState;
        public int dwStateMask;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)]
        public string szInfo = string.Empty;
        public int uVersionOrTimeout;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)]
        public string szInfoTitle = string.Empty;
        public uint dwInfoFlags;
        public Guid guidItem;
        public IntPtr hBalloonIcon;
    }

    /// <summary>The one call in this file the task brief specifically calls out
    /// for [DllImport]: NOTIFYICONDATAW's fixed-size tooltip/info buffers are
    /// exactly the shape LibraryImport does not marshal cleanly.</summary>
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool Shell_NotifyIcon(uint dwMessage, ref NOTIFYICONDATAW lpData);

    /// <summary>Pulls the icon already embedded in an exe's own resources —
    /// ApplicationIcon in Notebar.App.csproj embeds Assets/Notebar.ico into
    /// the built exe at index 0, so extracting from the running process's own
    /// exe path needs no extra file deployed alongside it.</summary>
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    internal static extern IntPtr ExtractIcon(IntPtr hInst, string lpszExeFileName, int nIconIndex);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool DestroyIcon(IntPtr hIcon);

    // --- popup menu (tray right-click) ---

    internal const uint MF_STRING = 0x0000;
    internal const uint MF_SEPARATOR = 0x0800;

    internal const uint TPM_RIGHTBUTTON = 0x0002;
    internal const uint TPM_RETURNCMD = 0x0100;

    [DllImport("user32.dll", SetLastError = true)]
    internal static extern IntPtr CreatePopupMenu();

    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool AppendMenu(IntPtr hMenu, uint uFlags, UIntPtr uIDNewItem, string? lpNewItem);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool DestroyMenu(IntPtr hMenu);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll", SetLastError = true)]
    internal static extern int TrackPopupMenu(
        IntPtr hMenu, uint uFlags, int x, int y, int nReserved, IntPtr hWnd, IntPtr prcRect);
}
