using Notebar.Core.Models;
using Notebar.Core.Schema;
using Notebar.Store;
using Xunit;

namespace Notebar.Store.Tests;

public class SqliteTaskRepositoryTests : IDisposable
{
    private readonly TestDatabase _fixture = new();
    private readonly SqliteTaskRepository _repo;

    public SqliteTaskRepositoryTests() => _repo = new SqliteTaskRepository(_fixture.Db);
    public void Dispose() => _fixture.Dispose();

    [Fact]
    public void SeedsThreeColumnsInOrder()
    {
        var columns = _repo.Columns();
        Assert.Equal(["Queue", "Working", "Done"], columns.Select(c => c.Name));
        Assert.Equal(
            [BoardColumn.BacklogKind, BoardColumn.ActiveKind, BoardColumn.DoneKind],
            columns.Select(c => c.Kind));
    }

    [Fact]
    public void CreateRoundTripsIntoItsColumn()
    {
        var task = _repo.Create("Ship it", TaskSchema.QueueColumnId);
        var stored = Assert.Single(_repo.All());
        Assert.Equal(task, stored);
        Assert.Equal(TaskSchema.QueueColumnId, stored.ColumnId);
        Assert.Null(stored.CompletedAt);
    }

    [Fact]
    public void CreateAppendsWithinItsOwnColumn()
    {
        var a = _repo.Create("a", TaskSchema.QueueColumnId);
        var b = _repo.Create("b", TaskSchema.QueueColumnId);
        var c = _repo.Create("c", TaskSchema.WorkingColumnId);

        Assert.True(b.SortOrder > a.SortOrder);
        // c is in a different column, so it does not have to sort after b.
        Assert.Equal(TaskSchema.WorkingColumnId, c.ColumnId);
    }

    [Fact]
    public void UpdatePersistsTitleDetailPriorityAndDueDate()
    {
        var task = _repo.Create("draft", TaskSchema.QueueColumnId);
        var due = new DateTimeOffset(2026, 10, 1, 9, 0, 0, TimeSpan.Zero);
        _repo.Update(task with { Title = "final", DetailPlain = "with notes", Priority = 2, DueAt = due });

        var stored = Assert.Single(_repo.All());
        Assert.Equal("final", stored.Title);
        Assert.Equal("with notes", stored.DetailPlain);
        Assert.Equal(2, stored.Priority);
        Assert.Equal(due, stored.DueAt);
    }

    [Fact]
    public void UpdatingAnUnknownIdThrows() =>
        Assert.Throws<InvalidOperationException>(() =>
            _repo.Update(TaskItem.New("orphan", TaskSchema.QueueColumnId, 0)));

    /// The rule that lives in the repository rather than the UI, so every caller
    /// gets it for free.
    [Fact]
    public void MovingIntoDoneStampsCompletedAt()
    {
        var task = _repo.Create("thing", TaskSchema.QueueColumnId);
        var moved = _repo.Move(task.Id, TaskSchema.DoneColumnId, null, null);
        Assert.NotNull(moved.CompletedAt);
    }

    [Fact]
    public void MovingOutOfDoneClearsCompletedAt()
    {
        var task = _repo.Create("thing", TaskSchema.QueueColumnId);
        _repo.Move(task.Id, TaskSchema.DoneColumnId, null, null);
        var moved = _repo.Move(task.Id, TaskSchema.WorkingColumnId, null, null);
        Assert.Null(moved.CompletedAt);
    }

    /// Reordering within Done must not restamp — the completion time is when it
    /// was finished, not when it was last dragged.
    [Fact]
    public void ReorderingWithinDoneKeepsTheOriginalCompletionTime()
    {
        var a = _repo.Create("a", TaskSchema.DoneColumnId);
        var b = _repo.Create("b", TaskSchema.DoneColumnId);
        var stampedA = _repo.Move(a.Id, TaskSchema.DoneColumnId, null, b.Id);
        var first = stampedA.CompletedAt;

        var again = _repo.Move(a.Id, TaskSchema.DoneColumnId, b.Id, null);
        Assert.Equal(first, again.CompletedAt);
    }

    [Fact]
    public void MoveRepositionsWithinAColumn()
    {
        var a = _repo.Create("a", TaskSchema.QueueColumnId);
        var b = _repo.Create("b", TaskSchema.QueueColumnId);
        var c = _repo.Create("c", TaskSchema.QueueColumnId);

        _repo.Move(c.Id, TaskSchema.QueueColumnId, a.Id, b.Id);

        var queue = _repo.All().Where(t => t.ColumnId == TaskSchema.QueueColumnId);
        Assert.Equal([a.Id, c.Id, b.Id], queue.Select(t => t.Id));
    }

    [Fact]
    public void DeleteRemovesTheRowAndIsIdempotent()
    {
        var task = _repo.Create("x", TaskSchema.QueueColumnId);
        _repo.Delete(task.Id);
        Assert.Empty(_repo.All());
        _repo.Delete(task.Id);
    }

    [Fact]
    public void SearchFindsByTitleAndDetail()
    {
        var a = _repo.Create("Deploy the panel", TaskSchema.QueueColumnId);
        var b = _repo.Create("Buy milk", TaskSchema.QueueColumnId);
        _repo.Update(b with { DetailPlain = "semi-skimmed" });

        Assert.Equal([a.Id], _repo.Search("panel").Select(t => t.Id));
        Assert.Equal([b.Id], _repo.Search("skimmed").Select(t => t.Id));
    }

    [Fact]
    public void AllIsOrderedByColumnThenPosition()
    {
        var q = _repo.Create("q", TaskSchema.QueueColumnId);
        var d = _repo.Create("d", TaskSchema.DoneColumnId);
        var w = _repo.Create("w", TaskSchema.WorkingColumnId);

        Assert.Equal([q.Id, w.Id, d.Id], _repo.All().Select(t => t.Id));
    }
}
