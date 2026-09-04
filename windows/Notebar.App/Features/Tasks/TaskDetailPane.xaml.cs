using System.Globalization;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Notebar.App.Features.Notes;
using Notebar.App.Panel;
using Notebar.Core.Models;
using Windows.System;

namespace Notebar.App.Features.Tasks;

/// <summary>Code-behind for the task detail pane. Renders whatever TaskItem <see
/// cref="Show"/> was last called with and raises one event per field committed — see
/// TaskDetailPane.xaml's own remarks and TasksViewModel's remarks on why this control holds
/// no TaskItem field of its own.</summary>
internal sealed partial class TaskDetailPane : UserControl
{
    private static readonly string[] PriorityLabels = ["None", "Low", "High", "Urgent"];

    private PanelController? _panelController;
    private string? _taskId;

    // CalendarView raises SelectedDatesChanged for programmatic mutation too, not just
    // user clicks, so populating the picker from a task in Show() would otherwise write
    // that same date straight back to the database and re-enter Show() by way of
    // DueDateChanged -> TasksViewModel.UpdateDueDate -> WriteField -> SelectionChanged.
    // Guarded with try/finally in Show() so an exception mid-set can never leave this
    // stuck true, which would silently stop the user's own date edits from saving.
    private bool _settingDueDate;

    internal event Action<string, string>? TitleCommitted;
    internal event Action<string, string>? DetailCommitted;
    internal event Action<string, int>? PriorityChanged;
    internal event Action<string, DateTimeOffset?>? DueDateChanged;
    internal event Action<string>? DeleteRequested;
    internal event Action? BackRequested;

    internal TaskDetailPane() => InitializeComponent();

    /// <summary>Wires the two flyouts (priority, due date) to PanelController.HasOpenOverlay
    /// for their whole open duration — the defect table's "the panel collapsed out from
    /// under an open menu" row, same mechanism as NotesTab's all-notes Flyout and
    /// NoteTabStrip's rename Flyout.</summary>
    internal void Attach(PanelController panelController)
    {
        _panelController = panelController;
        // The parameter, not the field, inside every closure below -- see TasksTab.Attach's
        // own remarks on why a captured mutable field trips CS8602 under
        // TreatWarningsAsErrors while a captured parameter does not. Matches
        // NotesTab.Attach's identical `panelController.HasOpenOverlay = true` wiring for
        // its own Flyout.
        PriorityFlyout.Opened += (_, _) => panelController.HasOpenOverlay = true;
        PriorityFlyout.Closed += (_, _) => panelController.HasOpenOverlay = false;
        DueDateFlyout.Opened += (_, _) => panelController.HasOpenOverlay = true;
        DueDateFlyout.Closed += (_, _) => panelController.HasOpenOverlay = false;
    }

    /// <summary>Renders one task. Always reads from the TaskItem the caller hands in — never
    /// from a field this control kept from a previous call — so a stale row can never leak
    /// into the fields shown here.</summary>
    internal void Show(TaskItem task)
    {
        _taskId = task.Id;
        TitleBox.Text = task.Title;
        DetailBox.Text = task.DetailPlain;

        int priority = Math.Clamp(task.Priority, 0, PriorityLabels.Length - 1);
        PriorityButton.Content = "Priority: " + PriorityLabels[priority];

        _settingDueDate = true;
        try
        {
            DueDateCalendar.SelectedDates.Clear();
            if (task.DueAt is { } due)
            {
                DueDateButton.Content = "Due " + due.ToLocalTime().ToString("MMM d, yyyy", CultureInfo.InvariantCulture);
                DueDateCalendar.SelectedDates.Add(due);
            }
            else
            {
                DueDateButton.Content = "Set due date";
            }
        }
        finally
        {
            _settingDueDate = false;
        }

        string meta = "Updated " + RelativeTime.Format(task.UpdatedAt);
        if (task.CompletedAt is { } completedAt) meta += " · Completed " + RelativeTime.Format(completedAt);
        MetaLabel.Text = meta;
    }

    /// <summary>Focuses and selects the title field — TasksTab calls this right after
    /// opening the pane for a just-created task, which is this task's whole answer to the
    /// macOS defect where a new card's title had no reachable edit path at all.</summary>
    internal void FocusTitle()
    {
        TitleBox.Focus(FocusState.Programmatic);
        TitleBox.SelectAll();
    }

    private void OnBackClick(object sender, RoutedEventArgs e) => BackRequested?.Invoke();

    private void OnDeleteClick(object sender, RoutedEventArgs e)
    {
        if (_taskId is { } id) DeleteRequested?.Invoke(id);
    }

    private void OnTitleLostFocus(object sender, RoutedEventArgs e) => CommitTitle();

    private void OnTitleKeyDown(object sender, KeyRoutedEventArgs e)
    {
        // Enter commits without needing a blur -- matches NoteTabStrip's rename box.
        if (e.Key != VirtualKey.Enter) return;
        CommitTitle();
        e.Handled = true;
    }

    private void CommitTitle()
    {
        if (_taskId is not { } id) return;
        TitleCommitted?.Invoke(id, TitleBox.Text);
    }

    private void OnDetailLostFocus(object sender, RoutedEventArgs e)
    {
        if (_taskId is not { } id) return;
        DetailCommitted?.Invoke(id, DetailBox.Text);
    }

    private void OnPriorityNoneClick(object sender, RoutedEventArgs e) => CommitPriority(TaskCardVm.PriorityNone);
    private void OnPriorityLowClick(object sender, RoutedEventArgs e) => CommitPriority(TaskCardVm.PriorityLow);
    private void OnPriorityHighClick(object sender, RoutedEventArgs e) => CommitPriority(TaskCardVm.PriorityHigh);
    private void OnPriorityUrgentClick(object sender, RoutedEventArgs e) => CommitPriority(TaskCardVm.PriorityUrgent);

    private void CommitPriority(int priority)
    {
        if (_taskId is not { } id) return;
        PriorityButton.Content = "Priority: " + PriorityLabels[priority];
        PriorityChanged?.Invoke(id, priority);
    }

    private void OnDueDateSelected(CalendarView sender, CalendarViewSelectedDatesChangedEventArgs args)
    {
        if (_settingDueDate) return;
        if (_taskId is not { } id) return;
        if (args.AddedDates.Count == 0) return;

        DateTimeOffset due = args.AddedDates[0];
        DueDateButton.Content = "Due " + due.ToLocalTime().ToString("MMM d, yyyy", CultureInfo.InvariantCulture);
        DueDateChanged?.Invoke(id, due);
        DueDateFlyout.Hide();
    }

    private void OnClearDueDateClick(object sender, RoutedEventArgs e)
    {
        if (_taskId is not { } id) return;
        DueDateCalendar.SelectedDates.Clear();
        DueDateButton.Content = "Set due date";
        DueDateChanged?.Invoke(id, null);
        DueDateFlyout.Hide();
    }
}
