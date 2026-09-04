namespace Notebar.Core.Models;

/// <summary>A single task card.</summary>
public sealed record TaskItem(
    string Id,
    string Title,
    string DetailPlain,
    string ColumnId,
    double SortOrder,
    int Priority,
    DateTimeOffset? DueAt,
    DateTimeOffset? CompletedAt,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt)
{
    public static TaskItem New(string title, string columnId, double sortOrder)
    {
        var now = DateTimeOffset.UtcNow;
        return new TaskItem(Guid.NewGuid().ToString(), title, "", columnId, sortOrder,
                            0, null, null, now, now);
    }
}
