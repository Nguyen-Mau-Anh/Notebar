using Notebar.Core.Models;
using Notebar.Core.Schema;
using Notebar.Store;
using Xunit;

namespace Notebar.Store.Tests;

public class SqliteLinkRepositoryTests : IDisposable
{
    private readonly TestDatabase _fixture = new();
    private readonly SqliteLinkRepository _links;
    private readonly SqliteNoteRepository _notes;
    private readonly SqliteTaskRepository _tasks;

    public SqliteLinkRepositoryTests()
    {
        _links = new SqliteLinkRepository(_fixture.Db);
        _notes = new SqliteNoteRepository(_fixture.Db);
        _tasks = new SqliteTaskRepository(_fixture.Db);
    }

    public void Dispose() => _fixture.Dispose();

    [Fact]
    public void CreateRoundTrips()
    {
        var note = _notes.Create();
        var task = _tasks.Create("t", TaskSchema.QueueColumnId);
        var link = _links.Create(Link.New(
            new LinkTarget(LinkEntityType.Note, note.Id),
            new LinkTarget(LinkEntityType.Task, task.Id)));

        Assert.Equal([link], _links.Outgoing(new LinkTarget(LinkEntityType.Note, note.Id)));
        Assert.Equal([link], _links.Incoming(new LinkTarget(LinkEntityType.Task, task.Id)));
    }

    /// Backlinks are the reverse query. A note that links out must not appear in
    /// its own incoming list.
    [Fact]
    public void OutgoingAndIncomingAreNotSymmetric()
    {
        var a = _notes.Create();
        var b = _notes.Create();
        _links.Create(Link.New(
            new LinkTarget(LinkEntityType.Note, a.Id),
            new LinkTarget(LinkEntityType.Note, b.Id)));

        Assert.Empty(_links.Incoming(new LinkTarget(LinkEntityType.Note, a.Id)));
        Assert.Single(_links.Incoming(new LinkTarget(LinkEntityType.Note, b.Id)));
    }

    /// The unique constraint means inserting the same edge twice is not an error
    /// the user should ever see — chips are inserted by typing, and typing the
    /// same reference twice is normal.
    [Fact]
    public void CreatingTheSameEdgeTwiceIsIdempotent()
    {
        var a = _notes.Create();
        var b = _notes.Create();
        var edge = Link.New(new LinkTarget(LinkEntityType.Note, a.Id),
                            new LinkTarget(LinkEntityType.Note, b.Id));

        _links.Create(edge);
        _links.Create(edge with { Id = Guid.NewGuid().ToString() });

        Assert.Single(_links.Outgoing(new LinkTarget(LinkEntityType.Note, a.Id)));
    }

    /// One transaction: the chip's markup and the row behind it commit together.
    [Fact]
    public void CreateSavingNoteBodyWritesBothOrNeither()
    {
        var note = _notes.Create();
        var task = _tasks.Create("t", TaskSchema.QueueColumnId);
        string html = $"<p>see <a href=\"{LinkUrl.Build(LinkEntityType.Task, task.Id)}\">t</a></p>";

        _links.CreateSavingNoteBody(
            Link.New(new LinkTarget(LinkEntityType.Note, note.Id),
                     new LinkTarget(LinkEntityType.Task, task.Id)),
            note.Id, html, "see t");

        Assert.Equal(html, _notes.Fetch(note.Id)!.BodyHtml);
        Assert.Single(_links.Outgoing(new LinkTarget(LinkEntityType.Note, note.Id)));
    }

    [Fact]
    public void CreateSavingNoteBodyRollsBackIfTheNoteIsGone()
    {
        var task = _tasks.Create("t", TaskSchema.QueueColumnId);
        var link = Link.New(new LinkTarget(LinkEntityType.Note, "no-such-note"),
                            new LinkTarget(LinkEntityType.Task, task.Id));

        Assert.Throws<InvalidOperationException>(() =>
            _links.CreateSavingNoteBody(link, "no-such-note", "<p>x</p>", "x"));

        Assert.Empty(_links.Incoming(new LinkTarget(LinkEntityType.Task, task.Id)));
    }

    /// Deleting a note cascades to every link touching it, on either end.
    [Fact]
    public void DeletingANoteRemovesLinksInBothDirections()
    {
        var a = _notes.Create();
        var b = _notes.Create();
        _links.Create(Link.New(new LinkTarget(LinkEntityType.Note, a.Id),
                               new LinkTarget(LinkEntityType.Note, b.Id)));
        _links.Create(Link.New(new LinkTarget(LinkEntityType.Note, b.Id),
                               new LinkTarget(LinkEntityType.Note, a.Id)));

        _notes.Delete(a.Id);

        Assert.Empty(_links.Outgoing(new LinkTarget(LinkEntityType.Note, b.Id)));
        Assert.Empty(_links.Incoming(new LinkTarget(LinkEntityType.Note, b.Id)));
    }

    [Fact]
    public void DeletingATaskRemovesLinksInBothDirections()
    {
        var note = _notes.Create();
        var task = _tasks.Create("t", TaskSchema.QueueColumnId);
        _links.Create(Link.New(new LinkTarget(LinkEntityType.Note, note.Id),
                               new LinkTarget(LinkEntityType.Task, task.Id)));

        _tasks.Delete(task.Id);

        Assert.Empty(_links.Outgoing(new LinkTarget(LinkEntityType.Note, note.Id)));
    }

    /// One query per note load, not one per chip — this is what makes the
    /// tombstone check a set lookup.
    [Fact]
    public void ExistingTargetsCoversBothTables()
    {
        var note = _notes.Create();
        var task = _tasks.Create("t", TaskSchema.QueueColumnId);

        var targets = _links.ExistingTargets();

        Assert.Contains(new LinkTarget(LinkEntityType.Note, note.Id), targets);
        Assert.Contains(new LinkTarget(LinkEntityType.Task, task.Id), targets);
        Assert.DoesNotContain(new LinkTarget(LinkEntityType.Note, task.Id), targets);
    }
}
