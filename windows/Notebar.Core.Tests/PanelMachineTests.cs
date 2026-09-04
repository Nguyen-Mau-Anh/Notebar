using Notebar.Core.Panel;
using Xunit;

namespace Notebar.Core.Tests;

public class PanelMachineTests
{
    private static (PanelState, IReadOnlyList<PanelEffect>) Reduce(
        PanelState state, PanelEvent evt, PanelContext? context = null) =>
        PanelMachine.Reduce(state, evt, context ?? PanelContext.Idle);

    [Fact]
    public void EnteringTriggerStartsDwell()
    {
        var (state, effects) = Reduce(PanelState.Hidden, PanelEvent.CursorEnteredTrigger);
        Assert.Equal(PanelState.Hidden, state);
        Assert.Equal(new PanelEffect[]
        {
            new PanelEffect.StartTimer(PanelTimerKind.EdgeDwell),
            new PanelEffect.SetPollRate(PollRate.Active),
        }, effects);
    }

    [Fact]
    public void LeavingTriggerCancelsDwell()
    {
        var (state, effects) = Reduce(PanelState.Hidden, PanelEvent.CursorLeftTrigger);
        Assert.Equal(PanelState.Hidden, state);
        Assert.Equal(new PanelEffect[]
        {
            new PanelEffect.CancelTimer(PanelTimerKind.EdgeDwell),
            new PanelEffect.SetPollRate(PollRate.Idle),
        }, effects);
    }

    [Fact]
    public void DwellElapsedExpands()
    {
        var (state, effects) = Reduce(PanelState.Hidden, PanelEvent.EdgeDwellElapsed);
        Assert.Equal(PanelState.Expanding, state);
        Assert.Equal(new PanelEffect[] { new PanelEffect.ShowPanel() }, effects);
    }

    [Fact]
    public void ExpandingCompletes()
    {
        var (state, effects) = Reduce(PanelState.Expanding, PanelEvent.AnimationFinished);
        Assert.Equal(PanelState.Expanded, state);
        Assert.Empty(effects);
    }

    /// Leaving an open panel only *arms* the collapse. Whether it is allowed to
    /// fire is decided when the timer elapses, against a fresh context.
    [Fact]
    public void LeavingPanelStartsExitTimer()
    {
        var (state, effects) = Reduce(PanelState.Expanded, PanelEvent.CursorLeftPanel);
        Assert.Equal(PanelState.Expanded, state);
        Assert.Equal(new PanelEffect[]
        {
            new PanelEffect.StartTimer(PanelTimerKind.ExitDwell),
        }, effects);
    }

    [Fact]
    public void ReturningCancelsExitTimer()
    {
        var (state, effects) = Reduce(PanelState.Expanded, PanelEvent.CursorEnteredPanel);
        Assert.Equal(PanelState.Expanded, state);
        Assert.Equal(new PanelEffect[]
        {
            new PanelEffect.CancelTimer(PanelTimerKind.ExitDwell),
        }, effects);
    }

    [Fact]
    public void ExitDwellCollapses()
    {
        var (state, effects) = Reduce(PanelState.Expanded, PanelEvent.ExitDwellElapsed);
        Assert.Equal(PanelState.Collapsing, state);
        Assert.Equal(new PanelEffect[] { new PanelEffect.HidePanel() }, effects);
    }

    [Fact]
    public void CollapseCompletes()
    {
        var (state, effects) = Reduce(PanelState.Collapsing, PanelEvent.AnimationFinished);
        Assert.Equal(PanelState.Hidden, state);
        Assert.Equal(new PanelEffect[] { new PanelEffect.SetPollRate(PollRate.Idle) }, effects);
    }

    /// Cursor came back mid-collapse: reverse without touching Hidden.
    [Fact]
    public void ReEntryDuringCollapseReverses()
    {
        foreach (var evt in new[] { PanelEvent.CursorEnteredPanel, PanelEvent.CursorEnteredTrigger })
        {
            var (state, effects) = Reduce(PanelState.Collapsing, evt);
            Assert.Equal(PanelState.Expanding, state);
            Assert.Equal(new PanelEffect[] { new PanelEffect.ShowPanel() }, effects);
        }
    }

    /// Escape overrides every suppression signal, pinning included.
    [Fact]
    public void EscapeAlwaysCollapses()
    {
        var pinned = PanelContext.Idle with { IsPinned = true, IsEditorFocused = true };
        foreach (var from in new[] { PanelState.Expanded, PanelState.Expanding })
        {
            var (state, effects) = Reduce(from, PanelEvent.EscapePressed, pinned);
            Assert.Equal(PanelState.Collapsing, state);
            Assert.Equal(new PanelEffect[]
            {
                new PanelEffect.HidePanel(),
                new PanelEffect.CancelTimer(PanelTimerKind.ExitDwell),
            }, effects);
        }
    }

    [Fact]
    public void ToggleFlips()
    {
        foreach (var from in new[] { PanelState.Hidden, PanelState.Collapsing })
        {
            var (state, effects) = Reduce(from, PanelEvent.ToggleRequested);
            Assert.Equal(PanelState.Expanding, state);
            Assert.Equal(new PanelEffect[]
            {
                new PanelEffect.ShowPanel(),
                new PanelEffect.SetPollRate(PollRate.Active),
            }, effects);
        }

        foreach (var from in new[] { PanelState.Expanded, PanelState.Expanding })
        {
            var (state, effects) = Reduce(from, PanelEvent.ToggleRequested);
            Assert.Equal(PanelState.Collapsing, state);
            Assert.Equal(new PanelEffect[] { new PanelEffect.HidePanel() }, effects);
        }
    }

    /// Anything not explicitly handled is inert: same state, no effects. This is
    /// what lets the controller fire events speculatively without checking state.
    [Fact]
    public void UnhandledPairsAreInert()
    {
        var (state, effects) = Reduce(PanelState.Hidden, PanelEvent.ExitDwellElapsed);
        Assert.Equal(PanelState.Hidden, state);
        Assert.Empty(effects);

        (state, effects) = Reduce(PanelState.Expanded, PanelEvent.EdgeDwellElapsed);
        Assert.Equal(PanelState.Expanded, state);
        Assert.Empty(effects);

        (state, effects) = Reduce(PanelState.Collapsing, PanelEvent.EscapePressed);
        Assert.Equal(PanelState.Collapsing, state);
        Assert.Empty(effects);
    }
}
