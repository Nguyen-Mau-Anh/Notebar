using Microsoft.UI.Dispatching;
using Notebar.App.Interop;
using Notebar.Core.Geometry;
using Notebar.Core.Panel;

namespace Notebar.App.Panel;

/// <summary>Turns PanelEffects into real window calls, and nothing else does.</summary>
/// <remarks>
/// The reducer decides; this executes. Keeping that line sharp is what makes
/// every transition testable without a window, which is the only reason the
/// panel's behaviour could be verified at all on a machine that cannot run it.
/// </remarks>
internal sealed class PanelController
{
    private readonly PanelWindow _window;
    private readonly CursorMonitor _cursor;
    private readonly DispatcherQueue _queue;
    private readonly Dictionary<PanelTimerKind, DispatcherQueueTimer> _timers = [];

    private PanelState _state = PanelState.Hidden;
    private DateTimeOffset? _lastKeystroke;
    private long _animationGeneration;
    private bool _insidePanel;
    private bool _insideTrigger;

    internal PanelState State => _state;
    internal bool IsPinned { get; set; }
    internal bool IsMaximized { get; set; }
    internal bool HasOpenOverlay { get; set; }
    internal bool IsDragging { get; set; }

    /// <summary>Asked fresh on every Send rather than cached as a flag.</summary>
    /// <remarks>
    /// On macOS this started life as a stored bool set by focus events, and it
    /// stuck true when a focused editor was destroyed — leaving the panel
    /// permanently un-collapsible, with no way back short of quitting. Deriving it
    /// from something observable at the moment the reducer reads it is what fixed
    /// that, and a delegate rather than a property is what stops it quietly
    /// becoming a cached flag again.
    /// </remarks>
    internal Func<bool> IsEditorFocusedProvider { get; set; } = () => false;

    internal PanelController(PanelWindow window, CursorMonitor cursor, DispatcherQueue queue)
    {
        _window = window;
        _cursor = cursor;
        _queue = queue;
        _cursor.Moved += OnCursorMoved;
    }

    internal void NoteKeystroke() => _lastKeystroke = DateTimeOffset.UtcNow;

    internal void Send(PanelEvent evt)
    {
        var context = SnapshotContext();
        var (next, effects) = PanelMachine.Reduce(_state, evt, context);
        _state = next;
        foreach (var effect in effects) Execute(effect);
    }

    private PanelContext SnapshotContext() => new(
        IsPinned: IsPinned,
        HasOpenOverlay: HasOpenOverlay,
        IsDragging: IsDragging || AnyMouseButtonDown(),
        IsEditorFocused: IsEditorFocusedProvider(),
        MsSinceLastKeystroke: _lastKeystroke is { } t
            ? (int)(DateTimeOffset.UtcNow - t).TotalMilliseconds
            : null,
        IsWindowActive: NativeMethods.GetForegroundWindow() == _window.Handle);

    /// <summary>A drag that ends outside the panel never delivers a drop event to
    /// us, so IsDragging set by a drag start would stay true forever. Polling the
    /// physical button state gives the flag a clearing path that does not depend
    /// on the drag source still existing — the same fix the macOS build needed.</summary>
    private static bool AnyMouseButtonDown() =>
        (NativeMethods.GetAsyncKeyState(0x01) & 0x8000) != 0 ||   // VK_LBUTTON
        (NativeMethods.GetAsyncKeyState(0x02) & 0x8000) != 0;     // VK_RBUTTON

    private void Execute(PanelEffect effect)
    {
        switch (effect)
        {
            case PanelEffect.StartTimer(var kind):
                StartTimer(kind);
                break;

            case PanelEffect.CancelTimer(var kind):
                CancelTimer(kind);
                break;

            case PanelEffect.ShowPanel:
                ShowPanel();
                break;

            case PanelEffect.HidePanel:
                HidePanel();
                break;

            case PanelEffect.SetPollRate(var rate):
                _cursor.SetRate(rate);
                break;
        }
    }

    private void StartTimer(PanelTimerKind kind)
    {
        CancelTimer(kind);
        var timer = _queue.CreateTimer();
        timer.IsRepeating = false;
        timer.Interval = TimeSpan.FromSeconds(kind == PanelTimerKind.EdgeDwell
            ? Settings.EdgeDwell
            : Settings.ExitDwell);
        timer.Tick += (_, _) =>
        {
            _timers.Remove(kind);
            Send(kind == PanelTimerKind.EdgeDwell
                ? PanelEvent.EdgeDwellElapsed
                : PanelEvent.ExitDwellElapsed);
        };
        _timers[kind] = timer;
        timer.Start();
    }

    private void CancelTimer(PanelTimerKind kind)
    {
        if (_timers.Remove(kind, out var timer)) timer.Stop();
    }

    private void ShowPanel()
    {
        long generation = ++_animationGeneration;
        var (dips, scale) = TargetFrame(IsMaximized ? FrameKind.Maximized : FrameKind.Expanded);
        _window.ApplyFrame(dips, scale);
        _window.ShowWithoutActivating();
        AfterAnimation(PanelTiming.ExpandDuration, generation);
    }

    private void HidePanel()
    {
        long generation = ++_animationGeneration;
        var (dips, scale) = TargetFrame(FrameKind.Collapsed);
        _window.ApplyFrame(dips, scale);
        AfterAnimation(PanelTiming.CollapseDuration, generation);
    }

    /// <summary>Fires AnimationFinished once the animation's duration has elapsed,
    /// unless a newer animation has started since.</summary>
    /// <remarks>
    /// The generation guard is what stops a stale completion from a cancelled
    /// collapse landing after a re-expand and immediately hiding the panel the
    /// user just opened. Without it the panel flickers, and only when someone
    /// moves the mouse back within the collapse duration — which is to say, only
    /// in front of a user and never in front of a developer.
    /// </remarks>
    private void AfterAnimation(double seconds, long generation)
    {
        var timer = _queue.CreateTimer();
        timer.IsRepeating = false;
        timer.Interval = TimeSpan.FromSeconds(seconds);
        timer.Tick += (_, _) =>
        {
            if (generation != _animationGeneration) return;
            Send(PanelEvent.AnimationFinished);
        };
        timer.Start();
    }

    private enum FrameKind { Collapsed, Expanded, Maximized }

    private (PanelRect Dips, double Scale) TargetFrame(FrameKind kind)
    {
        var cursor = NativeMethods.GetCursorPos(out var pt)
            ? new PanelPoint(pt.X, pt.Y)
            : new PanelPoint(0, 0);
        var physical = MonitorInfo.WorkAreaContaining(cursor, out double scale);
        var workArea = new PanelRect(physical.X / scale, physical.Y / scale,
                                     physical.Width / scale, physical.Height / scale);
        var rect = kind switch
        {
            FrameKind.Collapsed => PanelGeometry.Collapsed(workArea),
            FrameKind.Maximized => PanelGeometry.Maximized(workArea),
            _ => PanelGeometry.Expanded(workArea),
        };
        return (rect, scale);
    }

    /// <summary>Turns a cursor position into trigger and panel enter/leave events.</summary>
    /// <remarks>
    /// The trigger band is the *collapsed handle's* rect, not a full-height strip
    /// down the screen edge. That is what the user can see, and a strip they
    /// cannot see that opens a panel is a panel that opens by accident.
    /// </remarks>
    private void OnCursorMoved(PanelPoint physicalCursor)
    {
        var workAreaPhysical = MonitorInfo.WorkAreaContaining(physicalCursor, out double scale);
        var workArea = new PanelRect(
            workAreaPhysical.X / scale, workAreaPhysical.Y / scale,
            workAreaPhysical.Width / scale, workAreaPhysical.Height / scale);
        var cursor = PanelGeometry.ToDips(physicalCursor, scale);

        if (_state is PanelState.Hidden)
        {
            var handle = PanelGeometry.Collapsed(workArea);
            bool inside = handle.Contains(cursor);
            if (inside != _insideTrigger)
            {
                _insideTrigger = inside;
                Send(inside ? PanelEvent.CursorEnteredTrigger : PanelEvent.CursorLeftTrigger);
            }
            return;
        }

        var panel = IsMaximized ? PanelGeometry.Maximized(workArea) : PanelGeometry.Expanded(workArea);
        bool outside = EdgeZone.IsOutside(cursor, panel, Settings.ExitSlop);
        if (outside == _insidePanel)
        {
            _insidePanel = !outside;
            Send(outside ? PanelEvent.CursorLeftPanel : PanelEvent.CursorEnteredPanel);
        }

        // Cheap insurance against another app's fullscreen transition knocking
        // the panel out of the topmost band.
        if (_state is PanelState.Expanded) _window.ReassertTopmost();
    }
}
