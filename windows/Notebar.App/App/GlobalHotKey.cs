using Notebar.App.Interop;

namespace Notebar.App;

/// <summary>Ctrl+Shift+N, registered globally via RegisterHotKey.</summary>
/// <remarks>
/// TryRegister returns false rather than throwing when another app already
/// holds the combination — common, and not something the user did wrong.
/// Task 16's Settings surfaces that as "the shortcut is unavailable" rather
/// than the app crashing or the hotkey silently doing nothing.
/// </remarks>
internal sealed class GlobalHotKey : IDisposable
{
    private const int Id = 1;
    private const uint VkN = 0x4E;

    private readonly MessageWindow _messageWindow;
    private bool _registered;
    private bool _disposed;

    internal event Action? Pressed;

    internal GlobalHotKey(MessageWindow messageWindow)
    {
        _messageWindow = messageWindow;
        _messageWindow.HotKeyPressed += OnHotKeyPressed;
    }

    /// <summary>Attempts to claim Ctrl+Shift+N. False, not an exception, when
    /// another application already holds it.</summary>
    internal bool TryRegister()
    {
        _registered = NativeMethods.RegisterHotKey(
            _messageWindow.Handle,
            Id,
            NativeMethods.MOD_CONTROL | NativeMethods.MOD_SHIFT | NativeMethods.MOD_NOREPEAT,
            VkN);
        return _registered;
    }

    private void OnHotKeyPressed(int id)
    {
        if (id == Id) Pressed?.Invoke();
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;

        _messageWindow.HotKeyPressed -= OnHotKeyPressed;
        if (_registered)
            NativeMethods.UnregisterHotKey(_messageWindow.Handle, Id);
    }
}
