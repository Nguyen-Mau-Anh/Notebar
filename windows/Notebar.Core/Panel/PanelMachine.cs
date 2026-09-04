namespace Notebar.Core.Panel;

/// <summary>The panel's behaviour as a pure function.</summary>
/// <remarks>
/// This type must never touch UI, hold state, read a clock, or start a timer.
/// Time enters only as events (EdgeDwellElapsed, ExitDwellElapsed) that
/// PanelController schedules on the reducer's instruction. That is what makes
/// flicker scenarios — the bugs that are miserable to reproduce by hand — into
/// ordinary table tests.
/// </remarks>
public static class PanelMachine
{
    private static readonly IReadOnlyList<PanelEffect> None = [];

    public static (PanelState, IReadOnlyList<PanelEffect>) Reduce(
        PanelState state, PanelEvent evt, PanelContext context) =>
        (state, evt) switch
        {
            // Approaching the edge: arm the dwell timer, speed up polling.
            (PanelState.Hidden, PanelEvent.CursorEnteredTrigger) =>
                (PanelState.Hidden, [
                    new PanelEffect.StartTimer(PanelTimerKind.EdgeDwell),
                    new PanelEffect.SetPollRate(PollRate.Active)]),

            (PanelState.Hidden, PanelEvent.CursorLeftTrigger) =>
                (PanelState.Hidden, [
                    new PanelEffect.CancelTimer(PanelTimerKind.EdgeDwell),
                    new PanelEffect.SetPollRate(PollRate.Idle)]),

            (PanelState.Hidden, PanelEvent.EdgeDwellElapsed) =>
                (PanelState.Expanding, [new PanelEffect.ShowPanel()]),

            (PanelState.Expanding, PanelEvent.AnimationFinished) =>
                (PanelState.Expanded, None),

            // Leaving an open panel only *arms* the collapse. Whether it is
            // allowed to fire is decided when the timer elapses, against a
            // fresh context — 350 ms is long enough for things to change.
            (PanelState.Expanded, PanelEvent.CursorLeftPanel) =>
                ShouldCollapse(context)
                    ? (PanelState.Expanded, [new PanelEffect.StartTimer(PanelTimerKind.ExitDwell)])
                    : (PanelState.Expanded, None),

            (PanelState.Expanded, PanelEvent.CursorEnteredPanel) =>
                (PanelState.Expanded, [new PanelEffect.CancelTimer(PanelTimerKind.ExitDwell)]),

            (PanelState.Expanded, PanelEvent.ExitDwellElapsed) =>
                ShouldCollapse(context)
                    ? (PanelState.Collapsing, [new PanelEffect.HidePanel()])
                    : (PanelState.Expanded, None),

            (PanelState.Collapsing, PanelEvent.AnimationFinished) =>
                (PanelState.Hidden, [new PanelEffect.SetPollRate(PollRate.Idle)]),

            // Cursor came back mid-collapse: reverse without touching Hidden.
            (PanelState.Collapsing, PanelEvent.CursorEnteredPanel) or
            (PanelState.Collapsing, PanelEvent.CursorEnteredTrigger) =>
                (PanelState.Expanding, [new PanelEffect.ShowPanel()]),

            // Escape overrides every suppression signal, pinning included.
            (PanelState.Expanded, PanelEvent.EscapePressed) or
            (PanelState.Expanding, PanelEvent.EscapePressed) =>
                (PanelState.Collapsing, [
                    new PanelEffect.HidePanel(),
                    new PanelEffect.CancelTimer(PanelTimerKind.ExitDwell)]),

            (PanelState.Hidden, PanelEvent.ToggleRequested) or
            (PanelState.Collapsing, PanelEvent.ToggleRequested) =>
                (PanelState.Expanding, [
                    new PanelEffect.ShowPanel(),
                    new PanelEffect.SetPollRate(PollRate.Active)]),

            (PanelState.Expanded, PanelEvent.ToggleRequested) or
            (PanelState.Expanding, PanelEvent.ToggleRequested) =>
                (PanelState.Collapsing, [new PanelEffect.HidePanel()]),

            _ => (state, None),
        };

    /// <summary>Decides whether the panel is allowed to collapse right now.</summary>
    /// <remarks>
    /// Called twice per collapse: once when the cursor leaves (to decide whether
    /// to arm the exit timer at all) and again when that timer elapses.
    ///
    /// The trade-off: collapsing eagerly keeps the screen clean but interrupts
    /// you mid-thought; collapsing lazily never interrupts but leaves the panel
    /// loitering over your work. IsPinned, HasOpenOverlay, and IsDragging are
    /// hard requirements. Of the remaining three:
    ///
    ///   · IsEditorFocused      holds the panel open indefinitely, no grace
    ///                          period. Losing what you are typing because the
    ///                          mouse drifted is the worst failure this panel
    ///                          can have, and clicking into another app clears
    ///                          focus anyway, so this cannot strand it open.
    ///   · MsSinceLastKeystroke once focus is gone, TypingGrace still covers a
    ///                          recent burst of typing.
    ///   · IsWindowActive       deliberately unused. A window can become
    ///                          foreground from one stray click, which is too
    ///                          weak a signal to suppress collapse on.
    /// </remarks>
    internal static bool ShouldCollapse(PanelContext context)
    {
        if (context.IsPinned || context.HasOpenOverlay || context.IsDragging) return false;

        if (context.IsEditorFocused) return false;

        if (context.MsSinceLastKeystroke is { } ms && ms / 1000.0 <= PanelTiming.TypingGrace)
            return false;

        return true;
    }
}
