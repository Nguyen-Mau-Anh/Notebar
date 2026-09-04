using Notebar.Core.Models;
using Notebar.Store;
using Xunit;

namespace Notebar.Store.Tests;

/// <summary>Task 16 Step 2: the actual call path Settings -> Data -> Export Diagnostics
/// uses -- real notes in a real database, a real SqliteDiagnosticsRepository.Snapshot(),
/// rendered into a DiagnosticsEnvironment -- carries none of their content.</summary>
/// <remarks>
/// DiagnosticsTests in Notebar.Core.Tests already proves the *type* cannot carry note
/// content by construction (DiagnosticsEnvironment has no field a note's title or body
/// could occupy); this proves the real repository call feeding it nothing does either --
/// e.g. that a note's title never ends up smuggled into Path, or its body into
/// AppliedMigrations, by some accident upstream of the type itself.
/// </remarks>
public class DiagnosticsExportContentTests : IDisposable
{
    private const string SecretTitleA = "Launch codes";
    private const string SecretBodyA = "the launch codes are 4815162342";
    private const string SecretTitleB = "Party planning";
    private const string SecretBodyB = "do not tell anyone about the surprise party";

    private readonly TestDatabase _fixture = new();

    public void Dispose() => _fixture.Dispose();

    [Fact]
    public void RenderedDiagnosticsCarryNoNoteContent()
    {
        var notes = new SqliteNoteRepository(_fixture.Db);

        var first = notes.Create();
        notes.Update(first with { Title = SecretTitleA, BodyHtml = $"<p>{SecretBodyA}</p>", BodyPlain = SecretBodyA });

        var second = notes.Create();
        notes.Update(second with { Title = SecretTitleB, BodyHtml = $"<p>{SecretBodyB}</p>", BodyPlain = SecretBodyB });

        DatabaseDiagnostics snapshot = new SqliteDiagnosticsRepository(_fixture.Db).Snapshot();
        var environment = new DiagnosticsEnvironment(
            "0.1.0", "0", "Windows 11 26100",
            ["1920x1080 @ (0, 0), scale 1.0"], snapshot);

        string text = environment.RenderedText;

        Assert.DoesNotContain(SecretBodyA, text);
        Assert.DoesNotContain(SecretBodyB, text);
        Assert.DoesNotContain(SecretTitleA, text);
        Assert.DoesNotContain(SecretTitleB, text);
    }
}
