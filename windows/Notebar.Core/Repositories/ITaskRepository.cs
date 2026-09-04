using Notebar.Core.Models;

namespace Notebar.Core.Repositories;

/// <summary>Storage for the tasks board: its columns and the cards within
/// them.</summary>
/// <remarks>
/// Synchronous, for the same reason as <see cref="INoteRepository"/>: the store
/// is a local SQLite file behind a single connection, and every call is a
/// sub-millisecond local operation.
/// </remarks>
public interface ITaskRepository
{
    /// <summary>Every column across every board, ordered by SortOrder ascending.
    /// v1 seeds exactly one board, so in practice this is that board's three
    /// columns.</summary>
    IReadOnlyList<BoardColumn> Columns();

    /// <summary>Every task, ordered by its column's position, then its own
    /// SortOrder within that column.</summary>
    IReadOnlyList<TaskItem> All();

    /// <summary>Creates a task appended after the current last task in
    /// <paramref name="columnId"/> and persists it immediately.</summary>
    TaskItem Create(string title, string columnId);

    /// <summary>Persists every mutable field of an existing task and stamps
    /// UpdatedAt. The row must already exist; unknown ids throw.</summary>
    void Update(TaskItem task);

    /// <summary>Deletes a task. A no-op if id does not exist.</summary>
    void Delete(string id);

    /// <summary>Moves the task to <paramref name="columnId"/>, at a fractional
    /// SortOrder strictly between the two named neighbours (null for either
    /// bound means that end of the column). Entering a Done-kind column stamps
    /// CompletedAt; leaving one clears it; reordering within one leaves the
    /// existing stamp untouched — the completion time is when the work
    /// finished, not when the card was last dragged.</summary>
    TaskItem Move(string id, string columnId, string? beforeId, string? afterId);

    /// <summary>Full-text search over title and detail via task_fts, most
    /// relevant first. Empty for a blank query.</summary>
    IReadOnlyList<TaskItem> Search(string query);
}
