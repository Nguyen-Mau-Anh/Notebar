using System.Collections.ObjectModel;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;
using Notebar.App.Features;
using Notebar.App.Features.Linking;
using Notebar.App.Panel;
using Notebar.Core.Models;
using Notebar.Core.Repositories;
using Windows.ApplicationModel.DataTransfer;
using Windows.Foundation;

namespace Notebar.App.Features.Tasks;

/// <summary>Coordinates the three-column board and the one shared TaskDetailPane. See
/// TasksTab.xaml's own remarks on the slide-aside layout, and TasksViewModel's remarks on
/// why a move never triggers a full column rebuild the way create/delete/load do.</summary>
internal sealed partial class TasksTab : UserControl
{
    private TasksViewModel? _viewModel;
    private PanelController? _panelController;
    private PanelViewModel? _panelViewModel;

    private BoardColumn? _queueColumn;
    private BoardColumn? _workingColumn;
    private BoardColumn? _doneColumn;

    private readonly ObservableCollection<TaskCardVm> _queueItems = [];
    private readonly ObservableCollection<TaskCardVm> _workingItems = [];
    private readonly ObservableCollection<TaskCardVm> _doneItems = [];

    private bool _detailOpen;
    private bool _focusTitleOnOpen;

    internal TasksTab() => InitializeComponent();

    /// <summary>Wires everything up. Called once by RootPage.AttachController, mirroring
    /// NotesTab.Attach. panelViewModel is RootPage's own rail selection -- OnTaskRequested
    /// below is the only reason this needs it: switching a note's task-chip click to the
    /// Tasks tab, not just opening the task once there.</summary>
    internal void Attach(ITaskRepository taskRepository, PanelController panelController, PanelViewModel panelViewModel)
    {
        _panelController = panelController;
        _panelViewModel = panelViewModel;

        // A local, not the field, feeds every closure below: nullable flow analysis can
        // prove a just-assigned local stays non-null inside a lambda that captures it, but
        // not a mutable field (TreatWarningsAsErrors turns that CS8602 into a build
        // failure) -- the same reason NotesTab.Attach wires its own subscriptions as plain
        // method-group references instead of lambdas that close over `_viewModel`.
        var viewModel = new TasksViewModel(taskRepository);
        _viewModel = viewModel;
        viewModel.BoardChanged += OnBoardChanged;
        viewModel.SelectionChanged += OnSelectionChanged;
        viewModel.TaskChanged += RefreshCard;

        QueueList.ItemsSource = _queueItems;
        WorkingList.ItemsSource = _workingItems;
        DoneList.ItemsSource = _doneItems;

        Detail.Attach(panelController);
        Detail.BackRequested += OnDetailBackRequested;
        Detail.DeleteRequested += id => viewModel.DeleteTask(id);
        Detail.TitleCommitted += (id, title) => viewModel.RenameTask(id, title);
        Detail.DetailCommitted += (id, detail) => viewModel.UpdateDetail(id, detail);
        Detail.PriorityChanged += (id, priority) => viewModel.UpdatePriority(id, priority);
        Detail.DueDateChanged += (id, dueAt) => viewModel.UpdateDueDate(id, dueAt);

        // A static event with an instance handler outlives the instance that subscribed to
        // it -- normally the classic managed leak. Safe here only because TasksTab is a
        // process-lifetime singleton (RootPage.xaml builds exactly one, alive for as long as
        // the panel window is): there is nothing for this subscription to leak past. Never
        // unsubscribed for the same reason NotesTab's own Attach-time subscriptions aren't.
        LinkNavigation.TaskRequested += OnTaskRequested;

        viewModel.Load();
    }

    /// <summary>Task 15's note-chip and backlink clicks on a task target funnel through
    /// LinkNavigation.TaskRequested rather than reaching into this class directly (see
    /// LinkNavigation's own remarks). Switches the rail to the Tasks tab and opens the
    /// task's detail pane -- the same select/show path OnListSelectionChanged uses, so a
    /// chip click and a card click land in an identical state.</summary>
    private void OnTaskRequested(string taskId)
    {
        if (_viewModel is null) return;
        // The chip's target may have been deleted since the chip was written -- exactly
        // what tombstones exist for on the note side, but a race (deleted between the
        // click and this handler running) is still possible here. Do nothing rather than
        // open a tab onto a task that no longer exists.
        if (_viewModel.Find(taskId) is null) return;

        if (_panelViewModel is not null) _panelViewModel.Selection = AppTab.Tasks;
        _viewModel.SelectTask(taskId);
    }

    // --- board (create, structural rebuild) ---

    private void OnNewTaskClick(object sender, RoutedEventArgs e)
    {
        if (_viewModel is null) return;
        // Consumed by OnSelectionChanged below, which CreateTask's own SelectTask call
        // triggers synchronously -- the task-14 brief's answer to the macOS defect where a
        // new "New Task" card had no reachable rename path: this task is never left as an
        // inert placeholder, it opens straight into its own always-editable detail pane
        // with the title field already focused.
        _focusTitleOnOpen = true;
        _viewModel.CreateTask();
    }

    private void OnBoardChanged()
    {
        if (_viewModel is null) return;

        _queueColumn = _viewModel.Columns.FirstOrDefault(c => c.Kind == BoardColumn.BacklogKind);
        _workingColumn = _viewModel.Columns.FirstOrDefault(c => c.Kind == BoardColumn.ActiveKind);
        _doneColumn = _viewModel.Columns.FirstOrDefault(c => c.Kind == BoardColumn.DoneKind);

        QueueHeaderName.Text = _queueColumn?.Name ?? "Queue";
        WorkingHeaderName.Text = _workingColumn?.Name ?? "Working";
        DoneHeaderName.Text = _doneColumn?.Name ?? "Done";

        RebuildColumn(_queueItems, _queueColumn);
        RebuildColumn(_workingItems, _workingColumn);
        RebuildColumn(_doneItems, _doneColumn);
        RefreshCounts();

        bool empty = _viewModel.TotalTaskCount == 0;
        EmptyState.Visibility = empty ? Visibility.Visible : Visibility.Collapsed;
        SlideViewport.Visibility = empty ? Visibility.Collapsed : Visibility.Visible;
        TaskCountLabel.Text = _viewModel.TotalTaskCount.ToString();
    }

    private void RebuildColumn(ObservableCollection<TaskCardVm> items, BoardColumn? column)
    {
        items.Clear();
        if (column is null || _viewModel is null) return;
        foreach (TaskItem task in _viewModel.TasksInColumn(column.Id))
            items.Add(TaskCardVm.From(task));
    }

    private void RefreshCounts()
    {
        QueueCountLabel.Text = _queueItems.Count.ToString();
        WorkingCountLabel.Text = _workingItems.Count.ToString();
        DoneCountLabel.Text = _doneItems.Count.ToString();
    }

    /// <summary>Replaces the rendered card for one task. TaskCardVm is an immutable record
    /// with no change notification, so mutating the underlying TaskItem in TasksViewModel
    /// does not by itself repaint anything -- the instance already sitting in whichever
    /// ObservableCollection holds it has to be swapped for a Replace notification to fire
    /// at all. Without this, the board kept showing a task's old title, priority flag, and
    /// overdue-due-date styling until something else forced a full BoardChanged rebuild --
    /// the stale-copy bug class one layer up from TasksViewModel.WriteField's own
    /// defence.</summary>
    private void RefreshCard(string id)
    {
        if (_viewModel is null) return;
        TaskItem? task = _viewModel.Find(id);
        if (task is null) return;

        TaskCardVm vm = TaskCardVm.From(task);
        if (TryReplaceCard(_queueItems, vm)) return;
        if (TryReplaceCard(_workingItems, vm)) return;
        TryReplaceCard(_doneItems, vm);
    }

    private static bool TryReplaceCard(ObservableCollection<TaskCardVm> items, TaskCardVm vm)
    {
        int index = IndexOf(items, vm.Id);
        if (index < 0) return false;
        items[index] = vm;
        return true;
    }

    // --- selection / detail pane ---

    private void OnListSelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_viewModel is null) return;
        if (e.AddedItems.Count > 0 && e.AddedItems[0] is TaskCardVm vm)
            _viewModel.SelectTask(vm.Id);
    }

    private void OnSelectionChanged()
    {
        if (_viewModel is null) return;

        TaskItem? selected = _viewModel.SelectedTask;
        if (selected is null)
        {
            _focusTitleOnOpen = false;
            CloseDetail();
            return;
        }

        Detail.Show(selected);
        OpenDetail();
        if (_focusTitleOnOpen)
        {
            _focusTitleOnOpen = false;
            Detail.FocusTitle();
        }
    }

    private void OnDetailBackRequested() => _viewModel?.SelectTask(null);

    private void OpenDetail()
    {
        if (_detailOpen) return;
        _detailOpen = true;
        AnimateSlide(-SlideViewport.ActualWidth);
    }

    private void CloseDetail()
    {
        if (!_detailOpen)
        {
            ClearListSelections();
            return;
        }
        _detailOpen = false;
        AnimateSlide(0);
        ClearListSelections();
    }

    /// <summary>Clears every column ListView's own selection whenever the detail pane
    /// closes. Without this, re-clicking the same card that was just backed away from would
    /// not raise SelectionChanged at all (WinUI does not re-fire it when SelectedItem does
    /// not change), so the detail pane could never be reopened for that one card until some
    /// other card was selected first.</summary>
    private void ClearListSelections()
    {
        QueueList.SelectedItem = null;
        WorkingList.SelectedItem = null;
        DoneList.SelectedItem = null;
    }

    private void AnimateSlide(double toX)
    {
        var animation = new DoubleAnimation
        {
            To = toX,
            Duration = new Duration(TimeSpan.FromSeconds(Notebar.Core.Panel.PanelTiming.ExpandDuration)),
            EasingFunction = new QuadraticEase { EasingMode = EasingMode.EaseOut },
        };
        Storyboard.SetTarget(animation, SlideTransform);
        Storyboard.SetTargetProperty(animation, "X");
        var board = new Storyboard();
        board.Children.Add(animation);
        board.Begin();
    }

    private void OnSlideViewportSizeChanged(object sender, SizeChangedEventArgs e)
    {
        double width = e.NewSize.Width;
        double height = e.NewSize.Height;
        BoardHost.Width = width;
        DetailHost.Width = width;
        SlideViewport.Clip = new RectangleGeometry { Rect = new Rect(0, 0, width, height) };
        // No animation on a resize -- only a genuine open/close transition eases; snapping
        // straight to the correct offset here is what keeps the pane's edge glued to the
        // viewport edge while, e.g., Maximize resizes the panel out from under it.
        SlideTransform.X = _detailOpen ? -width : 0;
    }

    // --- drag and drop ---
    //
    // WinUI's ListView already does most of what the macOS build wrote by hand for
    // cross-group drag: CanDragItems + AllowDrop + CanReorderItems, on ObservableCollection
    // ItemsSource of the same element type across all three lists, moves the dragged item's
    // TaskCardVm between the lists' own collections on drop -- no manual DataPackage
    // plumbing needed. What is left to this class is exactly the two things the repository
    // does not know on its own: which neighbours the card landed between (read off the
    // target list's own post-drop order) and persisting that through Move.

    private void OnDragItemsStarting(object sender, DragItemsStartingEventArgs e)
    {
        if (_panelController is not null) _panelController.IsDragging = true;
    }

    private void OnDragItemsCompleted(ListViewBase sender, DragItemsCompletedEventArgs args)
    {
        // The controller's own mouse-button poll is the backstop for a drag that ends
        // outside the panel and never reaches this handler at all -- this clears the flag
        // for every ordinary completion, dropped or cancelled alike.
        if (_panelController is not null) _panelController.IsDragging = false;
        if (_viewModel is null) return;

        // DropResult is None for a drag released outside every valid target (cancelled by
        // construction, per product spec §6.3) -- nothing moved, so there is nothing to
        // persist. A plain click never reaches this handler at all: DragItemsStarting (and
        // therefore this, DragItemsCompleted) only fires once a real drag gesture begins.
        if (args.DropResult != DataPackageOperation.Move) return;
        if (args.Items.Count == 0 || args.Items[0] is not TaskCardVm dragged) return;

        (ObservableCollection<TaskCardVm> items, BoardColumn? column)[] columns =
        [
            (_queueItems, _queueColumn),
            (_workingItems, _workingColumn),
            (_doneItems, _doneColumn),
        ];

        foreach ((ObservableCollection<TaskCardVm> items, BoardColumn? column) in columns)
        {
            if (column is null) continue;
            int index = IndexOf(items, dragged.Id);
            if (index < 0) continue;

            string? beforeId = index > 0 ? items[index - 1].Id : null;
            string? afterId = index < items.Count - 1 ? items[index + 1].Id : null;
            _viewModel.MoveTask(dragged.Id, column.Id, beforeId, afterId);
            RefreshCounts();
            break;
        }
    }

    private static int IndexOf(ObservableCollection<TaskCardVm> items, string id)
    {
        for (int i = 0; i < items.Count; i++)
            if (items[i].Id == id) return i;
        return -1;
    }

    // --- toolbar action button hover (screen spec §2), same pattern as NotesTab's own. ---

    private void OnNewTaskPointerEntered(object sender, PointerRoutedEventArgs e) => SetActionHover(true);
    private void OnNewTaskPointerExited(object sender, PointerRoutedEventArgs e) => SetActionHover(false);

    private void SetActionHover(bool isHovering)
    {
        NewTaskHoverBg.Visibility = isHovering ? Visibility.Visible : Visibility.Collapsed;
        NewTaskIconOff.Visibility = isHovering ? Visibility.Collapsed : Visibility.Visible;
        NewTaskIconOn.Visibility = isHovering ? Visibility.Visible : Visibility.Collapsed;
    }
}
