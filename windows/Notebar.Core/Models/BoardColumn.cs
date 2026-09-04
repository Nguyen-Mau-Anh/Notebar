namespace Notebar.Core.Models;

/// <summary>A status column on a Board.</summary>
/// <remarks>
/// Kind drives the one behaviour rule the repository owns — moving a task into a
/// DoneKind column stamps CompletedAt, moving it out clears it — so it is a
/// string constant rather than a closed enum: it is schema data a future board
/// could extend, not a fixed set the type system should own.
/// </remarks>
public sealed record BoardColumn(
    string Id, string BoardId, string Name, string Kind, double SortOrder, int? WipLimit)
{
    /// <summary>Not-yet-started work. Seeded as "Queue".</summary>
    public const string BacklogKind = "backlog";
    /// <summary>In-progress work. Seeded as "Working".</summary>
    public const string ActiveKind = "active";
    /// <summary>Finished work. Seeded as "Done" — the kind the task repository
    /// checks to decide whether a moved task's CompletedAt is stamped or cleared.</summary>
    public const string DoneKind = "done";
}
