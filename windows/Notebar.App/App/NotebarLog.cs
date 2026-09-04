namespace Notebar.App;

/// <summary>The app's own in-memory log, read back by Settings -> Data's
/// Export Diagnostics.</summary>
/// <remarks>
/// macOS's <c>DiagnosticsExporter</c> reads the last hour straight out of the
/// unified log via <c>OSLogStore</c> -- there is nothing to write to, the
/// system already keeps it. Windows has no equivalent this app can read back
/// without extra plumbing (the Event Log needs a registered provider and,
/// for a per-user app, more ceremony than a diagnostics button justifies), so
/// this keeps its own small ring buffer instead: capped at
/// <see cref="Capacity"/> entries, oldest dropped first. That is enough for a
/// session's worth of the handful of events this app actually logs (the
/// database-open fallback, tray/hotkey failures) without growing unbounded
/// over a long-running session.
///
/// <para>Never note or task content -- nothing in this app logs either, and
/// every call site here passes a fixed, hand-written message plus counts or
/// ids at most, the same rule <see cref="Notebar.Core.Models.DiagnosticsEnvironment"/>
/// enforces structurally for the environment half of the export.</para>
/// </remarks>
internal static class NotebarLog
{
    private const int Capacity = 500;

    private static readonly object Gate = new();
    private static readonly Queue<string> Entries = new();

    internal static void Info(string message) => Append("INFO", message);
    internal static void Warn(string message) => Append("WARN", message);
    internal static void Error(string message) => Append("ERROR", message);

    private static void Append(string level, string message)
    {
        string line = $"{DateTimeOffset.Now:yyyy-MM-ddTHH:mm:ss.fffzzz} [{level}] {message}";
        lock (Gate)
        {
            Entries.Enqueue(line);
            while (Entries.Count > Capacity) Entries.Dequeue();
        }
    }

    /// <summary>Every buffered entry, oldest first, as plain text -- what
    /// DiagnosticsExporter appends after the environment block.</summary>
    internal static string RenderedText()
    {
        lock (Gate)
        {
            return Entries.Count == 0
                ? "(no log entries recorded this session)"
                : string.Join(Environment.NewLine, Entries);
        }
    }
}
