using Microsoft.UI.Dispatching;
using Notebar.App.Interop;
using Notebar.Core.Geometry;
using Notebar.Core.Panel;

namespace Notebar.App.Panel;

/// <summary>Polls the cursor position on a dispatcher timer.</summary>
/// <remarks>
/// Polling rather than a mouse hook, deliberately and permanently. A low-level
/// mouse hook would give exact movement, and would also require the app to sit in
/// every application's input path, trip antivirus heuristics, and be the Windows
/// equivalent of the Accessibility permission this project has always refused.
/// GetCursorPos needs no permission at all.
///
/// The cost is answered by the two rates: 10 Hz while the cursor is nowhere near
/// the edge, 60 Hz once it is close or the panel is open. A 10 Hz timer calling
/// one user32 function is not measurable against an idle machine, and the app
/// spends almost all of its life there.
/// </remarks>
internal sealed class CursorMonitor : IDisposable
{
    private readonly DispatcherQueueTimer _timer;
    private PollRate _rate = PollRate.Idle;

    internal event Action<PanelPoint>? Moved;

    internal CursorMonitor(DispatcherQueue queue)
    {
        _timer = queue.CreateTimer();
        _timer.IsRepeating = true;
        _timer.Interval = IntervalFor(PollRate.Idle);
        _timer.Tick += (_, _) => Poll();
    }

    internal void Start() => _timer.Start();

    internal void Stop() => _timer.Stop();

    internal void SetRate(PollRate rate)
    {
        if (_rate == rate) return;
        _rate = rate;
        _timer.Interval = IntervalFor(rate);
    }

    private static TimeSpan IntervalFor(PollRate rate) => rate switch
    {
        PollRate.Active => TimeSpan.FromMilliseconds(1000.0 / 60),
        _ => TimeSpan.FromMilliseconds(100),
    };

    private void Poll()
    {
        if (NativeMethods.GetCursorPos(out var pt))
            Moved?.Invoke(new PanelPoint(pt.X, pt.Y));
    }

    public void Dispose() => _timer.Stop();
}
