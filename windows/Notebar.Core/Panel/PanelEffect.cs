namespace Notebar.Core.Panel;

/// <summary>Side effects the reducer requests. PanelController is the only code
/// that turns these into real Win32 and XAML calls — that separation is what
/// makes every transition testable without a window.</summary>
public abstract record PanelEffect
{
    private PanelEffect() { }

    public sealed record StartTimer(PanelTimerKind Timer) : PanelEffect;
    public sealed record CancelTimer(PanelTimerKind Timer) : PanelEffect;
    public sealed record ShowPanel : PanelEffect;
    public sealed record HidePanel : PanelEffect;
    public sealed record SetPollRate(PollRate Rate) : PanelEffect;
}
