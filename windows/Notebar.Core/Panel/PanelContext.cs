namespace Notebar.Core.Panel;

/// <summary>The suppression signals. Snapshotted by PanelController and passed
/// into every Reduce call.</summary>
public readonly record struct PanelContext(
    /// <summary>User pinned the panel, or summoned it by hotkey.</summary>
    bool IsPinned = false,
    /// <summary>A menu, flyout, or dialog is open.</summary>
    bool HasOpenOverlay = false,
    /// <summary>A drag is in flight.</summary>
    bool IsDragging = false,
    /// <summary>A text editor holds focus.</summary>
    bool IsEditorFocused = false,
    /// <summary>Milliseconds since the last keystroke, or null if none this session.</summary>
    int? MsSinceLastKeystroke = null,
    /// <summary>The panel window is the foreground window.</summary>
    bool IsWindowActive = false)
{
    /// <summary>A context with every suppression signal off.</summary>
    public static PanelContext Idle => new();
}
