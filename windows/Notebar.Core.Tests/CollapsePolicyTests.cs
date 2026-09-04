using Notebar.Core.Panel;
using Xunit;

namespace Notebar.Core.Tests;

public class CollapsePolicyTests
{
    // --- Hard invariants: never collapse under these. ---

    [Fact]
    public void PinnedNeverCollapses() =>
        Assert.False(PanelMachine.ShouldCollapse(PanelContext.Idle with { IsPinned = true }));

    [Fact]
    public void OpenOverlayNeverCollapses() =>
        Assert.False(PanelMachine.ShouldCollapse(PanelContext.Idle with { HasOpenOverlay = true }));

    [Fact]
    public void DraggingNeverCollapses() =>
        Assert.False(PanelMachine.ShouldCollapse(PanelContext.Idle with { IsDragging = true }));

    [Fact]
    public void IdlePanelCollapses() =>
        Assert.True(PanelMachine.ShouldCollapse(PanelContext.Idle));

    // --- The same signals, checked through Reduce, because the policy is applied
    //     twice per collapse and a regression could hit either call site. ---

    [Fact]
    public void PinnedSurvivesExitDwell()
    {
        var (state, effects) = PanelMachine.Reduce(
            PanelState.Expanded, PanelEvent.ExitDwellElapsed,
            PanelContext.Idle with { IsPinned = true });
        Assert.Equal(PanelState.Expanded, state);
        Assert.Empty(effects);
    }

    [Fact]
    public void DragInFlightSurvivesExit()
    {
        var (state, effects) = PanelMachine.Reduce(
            PanelState.Expanded, PanelEvent.CursorLeftPanel,
            PanelContext.Idle with { IsDragging = true });
        Assert.Equal(PanelState.Expanded, state);
        Assert.Empty(effects);
    }

    // --- A focused editor holds the panel open indefinitely, no grace period.
    //     Losing what you are typing because the mouse drifted is the worst
    //     failure this panel can have. ---

    [Fact]
    public void FocusedEditorNeverCollapsesWithNoKeystrokes() =>
        Assert.False(PanelMachine.ShouldCollapse(
            PanelContext.Idle with { IsEditorFocused = true, MsSinceLastKeystroke = null }));

    [Fact]
    public void FocusedEditorNeverCollapsesRegardlessOfKeystrokeAge() =>
        Assert.False(PanelMachine.ShouldCollapse(
            PanelContext.Idle with { IsEditorFocused = true, MsSinceLastKeystroke = 600_000 }));

    [Fact]
    public void FocusedEditorSurvivesExitDwell()
    {
        var (state, effects) = PanelMachine.Reduce(
            PanelState.Expanded, PanelEvent.ExitDwellElapsed,
            PanelContext.Idle with { IsEditorFocused = true });
        Assert.Equal(PanelState.Expanded, state);
        Assert.Empty(effects);
    }

    // --- Once focus is gone, TypingGrace still covers a recent burst. ---

    [Fact]
    public void UnfocusedRecentKeystrokeDoesNotCollapse() =>
        Assert.False(PanelMachine.ShouldCollapse(
            PanelContext.Idle with { IsEditorFocused = false, MsSinceLastKeystroke = 1_500 }));

    [Fact]
    public void UnfocusedStaleKeystrokeCollapses() =>
        Assert.True(PanelMachine.ShouldCollapse(
            PanelContext.Idle with { IsEditorFocused = false, MsSinceLastKeystroke = 5_000 }));

    /// IsWindowActive is deliberately unused. A window can become foreground from
    /// one stray click, which is too weak a signal to suppress collapse on. This
    /// test is what stops someone "fixing" that by wiring it in.
    [Fact]
    public void WindowActiveAloneDoesNotSuppress() =>
        Assert.True(PanelMachine.ShouldCollapse(PanelContext.Idle with { IsWindowActive = true }));
}
