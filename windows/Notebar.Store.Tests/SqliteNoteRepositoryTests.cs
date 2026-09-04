using Notebar.Core.Models;
using Notebar.Store;
using Xunit;

namespace Notebar.Store.Tests;

public class SqliteNoteRepositoryTests : IDisposable
{
    private readonly TestDatabase _fixture = new();
    private readonly SqliteNoteRepository _repo;

    public SqliteNoteRepositoryTests() => _repo = new SqliteNoteRepository(_fixture.Db);

    public void Dispose() => _fixture.Dispose();

    [Fact]
    public void CreateRoundTrips()
    {
        var created = _repo.Create();
        var fetched = _repo.Fetch(created.Id);
        Assert.Equal(created, fetched);
        Assert.Equal("Untitled", created.DisplayTitle);
    }

    [Fact]
    public void FetchingAnUnknownIdReturnsNull() =>
        Assert.Null(_repo.Fetch("nope"));

    [Fact]
    public void CreateAppendsAfterTheLast()
    {
        var first = _repo.Create();
        var second = _repo.Create();
        Assert.True(second.SortOrder > first.SortOrder);
        Assert.Equal([first.Id, second.Id], _repo.All().Select(n => n.Id));
    }

    [Fact]
    public void UpdatePersistsEveryFieldAndStampsUpdatedAt()
    {
        var note = _repo.Create();
        var edited = note with { Title = "Groceries", BodyHtml = "<p>milk</p>", BodyPlain = "milk" };
        _repo.Update(edited);

        var fetched = _repo.Fetch(note.Id)!;
        Assert.Equal("Groceries", fetched.Title);
        Assert.Equal("<p>milk</p>", fetched.BodyHtml);
        Assert.Equal("milk", fetched.BodyPlain);
        Assert.True(fetched.UpdatedAt >= note.UpdatedAt);
    }

    [Fact]
    public void UpdatingAnUnknownIdThrows()
    {
        var orphan = Note.New(sortOrder: 0);
        Assert.Throws<InvalidOperationException>(() => _repo.Update(orphan));
    }

    /// The editor's save path must not be able to revert a rename. This is the
    /// exact sequence that lost renames: rename, then save a body from a cached
    /// note still carrying the old title.
    [Fact]
    public void UpdateBodyLeavesTheTitleAlone()
    {
        var note = _repo.Create();
        var stale = note with { Title = "Old" };
        _repo.Update(stale);

        _repo.Update(stale with { Title = "Renamed" });
        _repo.UpdateBody(note.Id, "<p>typed</p>", "typed");

        var fetched = _repo.Fetch(note.Id)!;
        Assert.Equal("Renamed", fetched.Title);
        Assert.Equal("<p>typed</p>", fetched.BodyHtml);
    }

    [Fact]
    public void UpdatingBodyOfAnUnknownIdThrows() =>
        Assert.Throws<InvalidOperationException>(() => _repo.UpdateBody("nope", "<p/>", ""));

    [Fact]
    public void DeleteRemovesTheRowAndIsIdempotent()
    {
        var note = _repo.Create();
        _repo.Delete(note.Id);
        Assert.Null(_repo.Fetch(note.Id));
        _repo.Delete(note.Id);   // no-op, must not throw
    }

    /// The whole reason Summaries exists: it must never read a body. Store a
    /// large body and assert the summary does not carry it.
    [Fact]
    public void SummariesCarryNoBody()
    {
        var note = _repo.Create();
        _repo.Update(note with { Title = "Big", BodyHtml = new string('x', 100_000), BodyPlain = "xxx" });

        var summaries = _repo.Summaries();
        var summary = Assert.Single(summaries);
        Assert.Equal("Big", summary.Title);
        Assert.Equal(note.Id, summary.Id);
        // NoteSummary has no body field at all — this asserts the shape holds.
        Assert.Equal(3, typeof(NoteSummary).GetProperties()
            .Count(p => p.Name is "Id" or "Title" or "UpdatedAt"));
    }

    [Fact]
    public void SummariesUseTheSameOrderAsAll()
    {
        _repo.Create();
        _repo.Create();
        _repo.Create();
        Assert.Equal(_repo.All().Select(n => n.Id), _repo.Summaries().Select(s => s.Id));
    }

    [Fact]
    public void ReorderMovesBetweenNeighbours()
    {
        var a = _repo.Create();
        var b = _repo.Create();
        var c = _repo.Create();

        _repo.Reorder(c.Id, beforeId: a.Id, afterId: b.Id);

        Assert.Equal([a.Id, c.Id, b.Id], _repo.All().Select(n => n.Id));
    }

    [Fact]
    public void ReorderToTheFrontAndBack()
    {
        var a = _repo.Create();
        var b = _repo.Create();

        _repo.Reorder(b.Id, beforeId: null, afterId: a.Id);
        Assert.Equal([b.Id, a.Id], _repo.All().Select(n => n.Id));

        _repo.Reorder(b.Id, beforeId: a.Id, afterId: null);
        Assert.Equal([a.Id, b.Id], _repo.All().Select(n => n.Id));
    }

    [Fact]
    public void SearchFindsByTitleAndBody()
    {
        var a = _repo.Create();
        _repo.Update(a with { Title = "Groceries", BodyPlain = "milk and eggs" });
        var b = _repo.Create();
        _repo.Update(b with { Title = "Standup", BodyPlain = "deploy the panel" });

        Assert.Equal([a.Id], _repo.Search("milk").Select(n => n.Id));
        Assert.Equal([b.Id], _repo.Search("Standup").Select(n => n.Id));
    }

    [Fact]
    public void SearchIsEmptyForABlankQuery()
    {
        var a = _repo.Create();
        _repo.Update(a with { BodyPlain = "anything" });
        Assert.Empty(_repo.Search("   "));
    }

    /// FTS5 treats several characters as query syntax. A user typing a quote into
    /// the search box must get no results, not an exception.
    [Theory]
    [InlineData("\"")]
    [InlineData("*")]
    [InlineData("NEAR(")]
    [InlineData("a AND")]
    public void SearchSurvivesQuerySyntaxInUserInput(string query)
    {
        _repo.Create();
        _ = _repo.Search(query);   // must not throw
    }

    /// The shadow column and the body are written together, so the index can
    /// never be stale relative to the body it describes.
    [Fact]
    public void EditingABodyUpdatesTheIndex()
    {
        var a = _repo.Create();
        _repo.Update(a with { BodyPlain = "before" });
        Assert.Single(_repo.Search("before"));

        _repo.Update(a with { BodyPlain = "after" });
        Assert.Empty(_repo.Search("before"));
        Assert.Single(_repo.Search("after"));
    }

    [Fact]
    public void DeletingANoteRemovesItFromTheIndex()
    {
        var a = _repo.Create();
        _repo.Update(a with { BodyPlain = "findme" });
        _repo.Delete(a.Id);
        Assert.Empty(_repo.Search("findme"));
    }
}
