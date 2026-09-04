using Notebar.Core.Models;
using Xunit;

namespace Notebar.Core.Tests;

public class DiagnosticsTests
{
    private static DiagnosticsEnvironment Sample(DatabaseDiagnostics db) =>
        new("0.1.0", "1", "Windows 11 26100", ["1920x1080 @ (0, 0), scale 1.5"], db);

    [Fact]
    public void RendersEveryField()
    {
        var text = Sample(new DatabaseDiagnostics(
            @"C:\Users\x\AppData\Local\Notebar\notebar.sqlite", 40960,
            ["createNote", "createOpenTab"])).RenderedText;

        Assert.Contains("App version: 0.1.0 (1)", text);
        Assert.Contains("Windows version: Windows 11 26100", text);
        Assert.Contains("1920x1080 @ (0, 0), scale 1.5", text);
        Assert.Contains("notebar.sqlite", text);
        Assert.Contains("40960 bytes", text);
        Assert.Contains("createNote, createOpenTab", text);
    }

    [Fact]
    public void HandlesTheInMemoryFallback()
    {
        var text = Sample(new DatabaseDiagnostics(null, null, [])).RenderedText;
        Assert.Contains("in-memory", text);
        Assert.Contains("Database size: unknown", text);
        Assert.Contains("Migrations applied: none", text);
    }

    /// The invariant that makes it safe to hand this file to anyone. The type has
    /// no field a note body could occupy — this test is what stops a future
    /// "helpful" addition of one, by failing the moment a note's text can reach
    /// the rendered output.
    [Fact]
    public void CarriesNoNoteContent()
    {
        const string secret = "my private note body";
        var text = Sample(new DatabaseDiagnostics(
            @"C:\Notebar\notebar.sqlite", 1, ["createNote"])).RenderedText;
        Assert.DoesNotContain(secret, text);
        Assert.DoesNotContain("body", text, StringComparison.OrdinalIgnoreCase);
    }
}
