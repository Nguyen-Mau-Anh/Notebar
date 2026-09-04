namespace Notebar.App.Features.Linking;

/// <summary>The seam a note chip pointing at a task, or a backlink row pointing at a task,
/// hands off through.</summary>
/// <remarks>
/// Task 14's Tasks board owns opening a task and showing its detail pane, and
/// Features/Tasks/ is off limits to Task 15 (see the task brief) -- rather than reach into
/// TasksTab directly, NotesTab.OnChipClicked and NotesTab.OnBacklinkSelected raise this
/// static event instead, and the board can subscribe once its own "open this task and show
/// its detail" API exists. Static, not instance-scoped: there is exactly one Tasks board in
/// the app, and both a note chip click and a backlink row click need to reach it without
/// either side holding a reference to the other.
///
/// No subscriber exists yet as of this task -- clicking a task chip or a task backlink row
/// today raises this event into the void. That is a known, reported gap (see the Task 15
/// report), not a silent one: the alternative was reaching into Features/Tasks/, which the
/// brief explicitly rules out.
/// </remarks>
internal static class LinkNavigation
{
    /// <summary>Raised with a task id whenever something wants the Tasks board to open that
    /// task's detail pane.</summary>
    internal static event Action<string>? TaskRequested;

    internal static void RequestTask(string taskId) => TaskRequested?.Invoke(taskId);
}
