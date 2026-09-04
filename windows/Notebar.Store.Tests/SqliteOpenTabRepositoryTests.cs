using Notebar.Core.Models;
using Notebar.Store;
using Xunit;

namespace Notebar.Store.Tests;

public class SqliteOpenTabRepositoryTests : IDisposable
{
    private readonly TestDatabase _fixture = new();
    private readonly SqliteOpenTabRepository _repo;

    public SqliteOpenTabRepositoryTests() => _repo = new SqliteOpenTabRepository(_fixture.Db);
    public void Dispose() => _fixture.Dispose();

    [Fact]
    public void StartsEmpty() => Assert.Empty(_repo.All());

    [Fact]
    public void ReplaceAllRoundTripsOrder()
    {
        var tabs = new[]
        {
            new OpenTab(Guid.NewGuid().ToString(), OpenTab.NoteKind, "note-a", 0, false),
            new OpenTab(Guid.NewGuid().ToString(), OpenTab.NoteKind, "note-b", 1, true),
            new OpenTab(Guid.NewGuid().ToString(), OpenTab.NoteKind, "note-c", 2, false),
        };

        _repo.ReplaceAll(tabs);

        Assert.Equal(tabs.Select(t => t.RefId), _repo.All().Select(t => t.RefId));
    }

    /// The strip's own invariant, not enforced by the schema: only the tab the
    /// caller marked active comes back active.
    [Fact]
    public void ExactlyOneTabCanBeActive()
    {
        var tabs = new[]
        {
            new OpenTab(Guid.NewGuid().ToString(), OpenTab.NoteKind, "note-a", 0, false),
            new OpenTab(Guid.NewGuid().ToString(), OpenTab.NoteKind, "note-b", 1, true),
        };

        _repo.ReplaceAll(tabs);

        var active = _repo.All().Where(t => t.IsActive).ToList();
        var activeTab = Assert.Single(active);
        Assert.Equal("note-b", activeTab.RefId);
    }

    [Fact]
    public void ReplacingWithAnEmptyListClearsTheStrip()
    {
        _repo.ReplaceAll([new OpenTab(Guid.NewGuid().ToString(), OpenTab.NoteKind, "note-a", 0, true)]);
        Assert.Single(_repo.All());

        _repo.ReplaceAll([]);

        Assert.Empty(_repo.All());
    }
}
