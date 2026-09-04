using System.Text;

namespace Notebar.Core.Models;

/// <summary>The environment half of an Export Diagnostics file.</summary>
/// <remarks>
/// Deliberately holds nothing else: every field is a fact about the machine or
/// the store, never a note or task's content, so RenderedText is safe to hand to
/// anyone regardless of what is actually in the database. The app gathers these
/// values and appends its own log excerpt, which this type has no part in.
/// </remarks>
public sealed record DiagnosticsEnvironment(
    string AppVersion,
    string BuildNumber,
    string OsVersion,
    /// <summary>One line per connected display, already formatted as plain text
    /// (e.g. "1920x1080 @ (0, 0), scale 1.5") — computed by the caller so this
    /// type never needs to know what a monitor handle is.</summary>
    IReadOnlyList<string> DisplayGeometry,
    DatabaseDiagnostics Database)
{
    public string RenderedText
    {
        get
        {
            var sb = new StringBuilder();
            sb.AppendLine($"App version: {AppVersion} ({BuildNumber})");
            sb.AppendLine($"Windows version: {OsVersion}");
            if (DisplayGeometry.Count == 0)
            {
                sb.AppendLine("Displays: none reported");
            }
            else
            {
                sb.AppendLine("Displays:");
                foreach (var line in DisplayGeometry) sb.AppendLine($"  - {line}");
            }
            sb.AppendLine($"Database path: {Database.Path ?? "(in-memory — on-disk store could not be opened)"}");
            sb.AppendLine(Database.SizeOnDisk is { } size
                ? $"Database size: {size} bytes"
                : "Database size: unknown");
            sb.AppendLine(Database.AppliedMigrations.Count == 0
                ? "Migrations applied: none"
                : $"Migrations applied: {string.Join(", ", Database.AppliedMigrations)}");
            return sb.ToString().TrimEnd();
        }
    }
}
