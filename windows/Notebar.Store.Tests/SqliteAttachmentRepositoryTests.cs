using Notebar.Store;
using Xunit;

namespace Notebar.Store.Tests;

// SqliteNoteRepository.UpdateBody is used below to exercise DeleteOrphans
// against real note rows — the whole point of the bug this repository once
// had is that "which attachments are referenced" is a fact about every note,
// not just the one a caller happens to be looking at.

public class SqliteAttachmentRepositoryTests : IDisposable
{
    private readonly TestDatabase _fixture = new();
    private readonly SqliteAttachmentRepository _repo;

    public SqliteAttachmentRepositoryTests() => _repo = new SqliteAttachmentRepository(_fixture.Db);
    public void Dispose() => _fixture.Dispose();

    [Fact]
    public void CreateRoundTripsIncludingTheBytes()
    {
        byte[] data = [1, 2, 3, 4, 5];
        var attachment = _repo.Create("image/png", data, 100, 200);

        var fetched = _repo.Fetch(attachment.Id);

        Assert.NotNull(fetched);
        Assert.Equal("image/png", fetched.MimeType);
        Assert.Equal(data, fetched.Data);
        Assert.Equal(100, fetched.Width);
        Assert.Equal(200, fetched.Height);
    }

    [Fact]
    public void FetchingAnUnknownIdReturnsNull() => Assert.Null(_repo.Fetch("no-such-id"));

    /// Saving one note must not delete another note's images. The old
    /// DeleteUnreferenced(referencedIds) took the saved note's asset ids and
    /// deleted everything else, which destroyed every image in every other note.
    [Fact]
    public void SavingOneNoteDoesNotDeleteAnotherNotesImage()
    {
        var notes = new SqliteNoteRepository(_fixture.Db);
        var a = _repo.Create("image/png", [1, 2, 3], 10, 10);
        var b = _repo.Create("image/png", [4, 5, 6], 10, 10);

        var noteA = notes.Create();
        notes.UpdateBody(noteA.Id, $"<img src=\"https://notebar.local/asset/{a.Id}\">", "");
        var noteB = notes.Create();
        notes.UpdateBody(noteB.Id, $"<img src=\"https://notebar.local/asset/{b.Id}\">", "");

        _repo.DeleteOrphans();

        Assert.NotNull(_repo.Fetch(a.Id));
        Assert.NotNull(_repo.Fetch(b.Id));
    }

    /// ...but an image no note references any more is still collected.
    [Fact]
    public void DeleteOrphansRemovesAnImageNoNoteReferences()
    {
        var notes = new SqliteNoteRepository(_fixture.Db);
        var orphan = _repo.Create("image/png", [1, 2, 3], 10, 10);
        var kept = _repo.Create("image/png", [4, 5, 6], 10, 10);

        var note = notes.Create();
        notes.UpdateBody(note.Id, $"<img src=\"https://notebar.local/asset/{kept.Id}\">", "");

        _repo.DeleteOrphans();

        Assert.Null(_repo.Fetch(orphan.Id));
        Assert.NotNull(_repo.Fetch(kept.Id));
    }
}
