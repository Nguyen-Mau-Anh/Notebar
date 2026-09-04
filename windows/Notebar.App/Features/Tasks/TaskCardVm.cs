using Notebar.Core.Models;

namespace Notebar.App.Features.Tasks;

/// <summary>A per-render projection of a task for the board's card template (screen spec
/// §5.1). TaskItem itself carries no notion of "is this overdue" or "which flag glyph, if
/// any" — those are display rules derived at render time, the same split NoteTabItem and
/// AllNotesRowItem already draw between a model and its per-render card.</summary>
/// <remarks>
/// Priority is stored as a plain 0-3 int (TaskSchema's <c>priority INTEGER NOT NULL DEFAULT
/// 0</c> carries no named levels of its own); this task treats it as
/// None/Low/High/Urgent, matching screen spec §5.1's rule that only the two upper levels —
/// High and Urgent — ever draw a flag at all.
/// </remarks>
internal sealed record TaskCardVm(
    string Id,
    string Title,
    bool ShowHighFlag,
    bool ShowUrgentFlag,
    bool ShowDueNormal,
    bool ShowDueOverdue,
    string DueLabel)
{
    internal const int PriorityNone = 0;
    internal const int PriorityLow = 1;
    internal const int PriorityHigh = 2;
    internal const int PriorityUrgent = 3;

    internal static TaskCardVm From(TaskItem task)
    {
        bool hasDue = task.DueAt is not null;
        // A completed task's own due date no longer counts as overdue — the work is done,
        // dragging it back out of Done (which clears CompletedAt) is what should make an
        // old due date read as overdue again, not the mere passage of time on a finished
        // card.
        bool overdue = hasDue && task.CompletedAt is null && task.DueAt < DateTimeOffset.Now;

        // An absolute date, not RelativeTime.Format: that formatter reads "how long ago",
        // and a due date is usually still in the future — feeding it a negative elapsed
        // span would clamp to "just now" for every upcoming due date instead of a real
        // date. ShowDueOverdue (styled in DangerBrush by TasksTab's card template) already
        // carries the "this is late" signal, so the label itself only needs to say when.
        string dueLabel = hasDue
            ? "Due " + task.DueAt!.Value.ToLocalTime().ToString("MMM d", System.Globalization.CultureInfo.InvariantCulture)
            : "";

        return new TaskCardVm(
            task.Id,
            task.Title.Length == 0 ? "Untitled task" : task.Title,
            ShowHighFlag: task.Priority == PriorityHigh,
            ShowUrgentFlag: task.Priority == PriorityUrgent,
            ShowDueNormal: hasDue && !overdue,
            ShowDueOverdue: overdue,
            DueLabel: dueLabel);
    }
}
