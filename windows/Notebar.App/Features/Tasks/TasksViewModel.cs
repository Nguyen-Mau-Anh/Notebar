using Notebar.Core.Models;
using Notebar.Core.Repositories;

namespace Notebar.App.Features.Tasks;

/// <summary>Board state for the Tasks tab: the seeded columns, every task, and which one (if
/// any) is open in the detail pane.</summary>
/// <remarks>
/// <para>
/// <b>One canonical copy, never two.</b> Task 10 wrote note A's body into note B; Task 12
/// wrote a stale cached title over a rename — both because something other than this class
/// held its own mutable copy of a row and later wrote it back wholesale. Every mutator here
/// (<see cref="RenameTask"/>, <see cref="UpdateDetail"/>, <see cref="UpdatePriority"/>,
/// <see cref="UpdateDueDate"/>) takes only an id plus the one field that changed, reads the
/// current row out of <c>_allTasks</c> at call time, and applies a <c>with</c> expression —
/// so every other field, including whichever one a concurrent drag just changed, rides
/// along untouched. <see cref="MoveTask"/> is the one path that touches ColumnId/SortOrder,
/// and it always writes through <see cref="ITaskRepository.Move"/>, which owns the
/// completion-stamping rule — this class never sets CompletedAt itself. TaskDetailPane
/// (Task 14's other half) holds no TaskItem field of its own for this same reason: every
/// value it shows comes from <see cref="TaskDetailPane.Show"/>'s parameter, and every commit
/// it raises carries only the one changed field, so it can never round-trip a stale ColumnId
/// or SortOrder back through <see cref="ITaskRepository.Update"/>.
/// </para>
/// <para>
/// <b>The rendered board is a second copy of this same fact.</b> TasksTab's three
/// <c>ObservableCollection&lt;TaskCardVm&gt;</c> hold an immutable, no-notification
/// snapshot of each task, taken once by <see cref="TaskCardVm.From"/>. This class being
/// canonical does nothing for a stale *card* on its own -- <see cref="TaskChanged"/> is
/// what tells TasksTab which id to re-project and swap into its collection in place.
/// Fired from every path that mutates a row already sitting on the board (<see
/// cref="WriteField"/>, <see cref="MoveTask"/>), never from <see cref="CreateTask"/> or
/// <see cref="DeleteTask"/> (already covered by <see cref="BoardChanged"/>'s full
/// rebuild).
/// </para>
/// </remarks>
internal sealed class TasksViewModel
{
    private readonly ITaskRepository _tasks;
    private IReadOnlyList<BoardColumn> _columns = [];
    private readonly List<TaskItem> _allTasks = [];

    /// <summary>Raised on a structural change to the board's task set — load, create, or
    /// delete — never on a reorder/move. TasksTab rebuilds its three column lists from
    /// <see cref="TasksInColumn"/> when this fires; a move already updated the on-screen
    /// ListViews itself (WinUI's own cross-list drag mechanics), and rebuilding here too
    /// would fight that in-flight visual state instead of just persisting it — see
    /// TasksTab.OnDragItemsCompleted.</summary>
    internal event Action? BoardChanged;

    /// <summary>Raised whenever SelectedTaskId changes, including to null, and also after a
    /// move that changes the *selected* task's own row (so the detail pane's read-only
    /// Completed/Updated labels stay current without touching whatever the user is mid-typing
    /// in its title/detail fields).</summary>
    internal event Action? SelectionChanged;

    /// <summary>Raised with a task's id whenever that task's own row changes in place --
    /// a field edit or a drag-move -- so TasksTab can re-project and swap just that one
    /// card. See the class remarks on why the canonical copy alone does not keep the
    /// board's rendered cards current.</summary>
    internal event Action<string>? TaskChanged;

    internal IReadOnlyList<BoardColumn> Columns => _columns;
    internal int TotalTaskCount => _allTasks.Count;
    internal string? SelectedTaskId { get; private set; }
    internal TaskItem? SelectedTask => SelectedTaskId is { } id ? Find(id) : null;

    /// <summary>Looks up any task by id, not only the selected one -- TasksTab.RefreshCard
    /// uses this to re-project a task that <see cref="TaskChanged"/> just named.</summary>
    internal TaskItem? Find(string id) => _allTasks.Find(t => t.Id == id);

    internal TasksViewModel(ITaskRepository tasks) => _tasks = tasks;

    /// <summary>Loads the board fresh. Call once, before anything else.</summary>
    internal void Load()
    {
        _columns = _tasks.Columns();
        _allTasks.Clear();
        _allTasks.AddRange(_tasks.All());
        BoardChanged?.Invoke();
    }

    /// <summary>Every task in one column, sorted by SortOrder ascending. Sorted explicitly
    /// here rather than trusted from <c>_allTasks</c>'s own order: MoveTask replaces a row
    /// in place (see its own remarks) rather than relocating it within the list, so after a
    /// drag this class's list order no longer matches sort_order for the column that moved —
    /// only each row's own SortOrder field does.</summary>
    internal IReadOnlyList<TaskItem> TasksInColumn(string columnId) =>
        _allTasks.Where(t => t.ColumnId == columnId).OrderBy(t => t.SortOrder).ToList();

    /// <summary>Creates a task in the first backlog-kind column (screen spec §2: "new tasks
    /// land in the first backlog-kind column" — there is one toolbar action, not one per
    /// group) and selects it immediately. TasksTab.OnNewTaskClick uses the selection this
    /// raises to open the detail pane and focus its title field, which is this task's answer
    /// to the macOS defect where a new "New Task" card had no way to be renamed — the card
    /// itself is never inline-editable; the detail pane it opens into is always
    /// editable.</summary>
    internal TaskItem CreateTask()
    {
        BoardColumn column = _columns.FirstOrDefault(c => c.Kind == BoardColumn.BacklogKind) ?? _columns[0];
        TaskItem created = _tasks.Create("New Task", column.Id);
        _allTasks.Add(created);
        BoardChanged?.Invoke();
        SelectTask(created.Id);
        return created;
    }

    internal void SelectTask(string? id)
    {
        if (SelectedTaskId == id) return;
        SelectedTaskId = id;
        SelectionChanged?.Invoke();
    }

    internal void RenameTask(string id, string title)
    {
        string trimmed = title.Trim();
        if (trimmed.Length == 0) trimmed = "Untitled task";
        WriteField(id, task => task with { Title = trimmed });
    }

    internal void UpdateDetail(string id, string detail) =>
        WriteField(id, task => task with { DetailPlain = detail });

    internal void UpdatePriority(string id, int priority) =>
        WriteField(id, task => task with { Priority = priority });

    internal void UpdateDueDate(string id, DateTimeOffset? dueAt) =>
        WriteField(id, task => task with { DueAt = dueAt });

    internal void DeleteTask(string id)
    {
        _tasks.Delete(id);
        _allTasks.RemoveAll(t => t.Id == id);
        BoardChanged?.Invoke();
        if (SelectedTaskId == id) SelectTask(null);
    }

    /// <summary>Persists a drag-drop move. <paramref name="beforeId"/>/<paramref
    /// name="afterId"/> are the two neighbours the card should land between in its new
    /// column (the WinUI ListView the card was dropped into has already rearranged itself
    /// visually — TasksTab reads its final neighbour ids straight off that ListView's own
    /// ItemsSource and passes them through here unchanged, never computing a SortOrder
    /// itself). ITaskRepository.Move is what decides CompletedAt — entering a Done-kind
    /// column stamps it, leaving clears it, reordering within Done preserves it — this
    /// method never touches that field.</summary>
    internal void MoveTask(string id, string columnId, string? beforeId, string? afterId)
    {
        TaskItem moved = _tasks.Move(id, columnId, beforeId, afterId);
        int index = _allTasks.FindIndex(t => t.Id == id);
        if (index >= 0) _allTasks[index] = moved;
        TaskChanged?.Invoke(id);
        if (SelectedTaskId == id) SelectionChanged?.Invoke();
    }

    /// <summary>Every mutator above funnels through here: read the current canonical row,
    /// apply only the one field the caller named, persist the whole row (ITaskRepository.Update
    /// is a full-row write), and store the result back as the new canonical row. Because
    /// <paramref name="apply"/> is always given <c>_allTasks[index]</c> — never a copy the
    /// caller has been holding onto — a field changed by some other path (a drag's ColumnId,
    /// another commit's Priority) is never overwritten with a stale value.</summary>
    private void WriteField(string id, Func<TaskItem, TaskItem> apply)
    {
        int index = _allTasks.FindIndex(t => t.Id == id);
        if (index < 0) return;

        TaskItem updated = apply(_allTasks[index]);
        _tasks.Update(updated);
        _allTasks[index] = updated;
        TaskChanged?.Invoke(id);
        if (SelectedTaskId == id) SelectionChanged?.Invoke();
    }
}
