namespace Notebar.App.Features.Linking;

/// <summary>The seam a note chip pointing at a task, or a backlink row pointing at a task,
/// hands off through.</summary>
/// <remarks>
/// Task 14's Tasks board owns opening a task and showing its detail pane, and
/// Features/Tasks/ was off limits to Task 15 while it was live (see the task brief) --
/// rather than reach into TasksTab directly, NotesTab.OnChipClicked and
/// NotesTab.OnBacklinkSelected raise this static event instead. Static, not
/// instance-scoped: there is exactly one Tasks board in the app, and both a note chip click
/// and a backlink row click need to reach it without either side holding a reference to the
/// other.
///
/// TasksTab.OnTaskRequested is now the one subscriber, wired once in TasksTab.Attach (see
/// its own remarks on why that subscription is never unsubscribed).
/// </remarks>
internal static class LinkNavigation
{
    /// <summary>Raised with a task id whenever something wants the Tasks board to open that
    /// task's detail pane.</summary>
    internal static event Action<string>? TaskRequested;

    internal static void RequestTask(string taskId) => TaskRequested?.Invoke(taskId);
}
