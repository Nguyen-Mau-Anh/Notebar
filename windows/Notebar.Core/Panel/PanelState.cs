namespace Notebar.Core.Panel;

public enum PanelState { Hidden, Expanding, Expanded, Collapsing }

public enum PanelTimerKind { EdgeDwell, ExitDwell }

public enum PollRate
{
    /// <summary>Cursor is far from the edge. 10 Hz.</summary>
    Idle,
    /// <summary>Cursor is near the edge or the panel is open. 60 Hz.</summary>
    Active,
}

public enum PanelEvent
{
    /// <summary>Cursor entered the narrow activation strip at the screen edge.</summary>
    CursorEnteredTrigger,
    /// <summary>Cursor left the activation strip before the dwell elapsed.</summary>
    CursorLeftTrigger,
    /// <summary>Cursor moved inside the panel's bounds.</summary>
    CursorEnteredPanel,
    /// <summary>Cursor moved further than ExitSlop outside the panel's bounds.</summary>
    CursorLeftPanel,
    /// <summary>The edge-dwell timer fired.</summary>
    EdgeDwellElapsed,
    /// <summary>The exit-dwell timer fired.</summary>
    ExitDwellElapsed,
    /// <summary>A show or hide animation finished.</summary>
    AnimationFinished,
    /// <summary>Global hotkey pressed, or the tray toggle chosen.</summary>
    ToggleRequested,
    EscapePressed,
}
