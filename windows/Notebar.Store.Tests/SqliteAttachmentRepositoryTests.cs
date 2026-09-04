using Notebar.Store;
using Xunit;

namespace Notebar.Store.Tests;

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

    [Fact]
    public void DeleteUnreferencedKeepsReferencedRowsAndRemovesTheRest()
    {
        var kept = _repo.Create("image/png", [1], 1, 1);
        var orphan = _repo.Create("image/png", [2], 1, 1);

        _repo.DeleteUnreferenced(new HashSet<string> { kept.Id });

        Assert.NotNull(_repo.Fetch(kept.Id));
        Assert.Null(_repo.Fetch(orphan.Id));
    }
}
