using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Windows.System;

namespace Notebar.App.Features.Notes;

/// <summary>Code-behind for the tab strip: renders NotesViewModel.OpenNotes as tabs and
/// raises NoteSelected/NoteCloseRequested/NoteRenamed for NotesTab to act on. Owns none of
/// the actual note mutation itself -- see NoteTabStrip.xaml's own remarks and NotesTab's,
/// which is why closing the active tab needs to flush the editor first.</summary>
internal sealed partial class NoteTabStrip : UserControl
{
    private NotesViewModel? _viewModel;

    // A single shared Flyout + TextBox for renaming, shown at whichever tab was
    // double-tapped, rather than one per tab -- only one rename can ever be in progress at a
    // time, and this sidesteps needing per-item mutable "is this tab editing" state in the
    // data template entirely.
    private readonly Flyout _renameFlyout;
    private readonly TextBox _renameBox;
    private string? _renamingNoteId;
    private bool _renameHandled;

    internal event Action<string>? NoteSelected;
    internal event Action<string>? NoteCloseRequested;
    internal event Action<string, string>? NoteRenamed;

    internal NoteTabStrip()
    {
        InitializeComponent();

        _renameBox = new TextBox { Width = 160 };
        _renameBox.KeyDown += OnRenameBoxKeyDown;
        _renameFlyout = new Flyout { Content = _renameBox };
        _renameFlyout.Closed += OnRenameFlyoutClosed;
    }

    /// <summary>Subscribes to the view model and draws the current strip. Safe to call more
    /// than once (NotesTab.Attach only ever calls it once in practice, but re-binding to a
    /// different view model would not leak the old subscriptions).</summary>
    internal void Bind(NotesViewModel viewModel)
    {
        if (_viewModel is not null)
        {
            _viewModel.TabsChanged -= OnModelChanged;
            _viewModel.ActiveNoteChanged -= OnModelChanged;
        }

        _viewModel = viewModel;
        _viewModel.TabsChanged += OnModelChanged;
        _viewModel.ActiveNoteChanged += OnModelChanged;
        Rebuild();
    }

    private void OnModelChanged() => Rebuild();

    private void Rebuild()
    {
        if (_viewModel is null)
        {
            TabsList.ItemsSource = null;
            return;
        }

        string? activeId = _viewModel.ActiveNoteId;
        TabsList.ItemsSource = _viewModel.OpenNotes
            .Select(note => new NoteTabItem(note.Id, note.DisplayTitle, note.Id == activeId))
            .ToList();
    }

    private void OnTabTapped(object sender, TappedRoutedEventArgs e)
    {
        if (((FrameworkElement)sender).DataContext is NoteTabItem item)
            NoteSelected?.Invoke(item.Id);
    }

    private void OnTabPointerEntered(object sender, PointerRoutedEventArgs e)
    {
        var grid = (Grid)sender;
        if (grid.FindName("HoverBg") is Border hoverBg) hoverBg.Visibility = Visibility.Visible;
        if (grid.FindName("CloseButton") is Button closeButton) closeButton.Visibility = Visibility.Visible;
    }

    private void OnTabPointerExited(object sender, PointerRoutedEventArgs e)
    {
        var grid = (Grid)sender;
        bool isActive = grid.DataContext is NoteTabItem item && item.IsActive;
        if (grid.FindName("HoverBg") is Border hoverBg) hoverBg.Visibility = Visibility.Collapsed;
        if (grid.FindName("CloseButton") is Button closeButton)
            closeButton.Visibility = isActive ? Visibility.Visible : Visibility.Collapsed;
    }

    private void OnCloseButtonClick(object sender, RoutedEventArgs e)
    {
        if (((FrameworkElement)sender).DataContext is NoteTabItem item)
            NoteCloseRequested?.Invoke(item.Id);
    }

    // --- rename ---

    private void OnTitleDoubleTapped(object sender, DoubleTappedRoutedEventArgs e)
    {
        if (((FrameworkElement)sender).DataContext is not NoteTabItem item) return;

        _renamingNoteId = item.Id;
        _renameHandled = false;
        _renameBox.Text = item.DisplayTitle;
        _renameFlyout.ShowAt((FrameworkElement)sender);
        _renameBox.SelectAll();
        _renameBox.Focus(FocusState.Programmatic);
    }

    private void OnRenameBoxKeyDown(object sender, KeyRoutedEventArgs e)
    {
        if (e.Key == VirtualKey.Enter)
        {
            _renameHandled = true;
            CommitRename();
            _renameFlyout.Hide();
            e.Handled = true;
        }
        else if (e.Key == VirtualKey.Escape)
        {
            // Cancel, never commit -- a blank or edited draft here must revert to the
            // previous title, which is exactly what happens by doing nothing: the tab
            // strip's own display already shows the note's real title underneath this
            // flyout, untouched.
            _renameHandled = true;
            _renameFlyout.Hide();
            e.Handled = true;
        }
    }

    /// <summary>Covers every dismissal path the two explicit key handlers above do not:
    /// clicking away (WinUI Flyout is light-dismiss by default) is the equivalent of the
    /// macOS build's onChange(isTitleFieldFocused) blur-commits behaviour, so it commits
    /// here rather than silently discarding the edit.</summary>
    private void OnRenameFlyoutClosed(object? sender, object e)
    {
        if (!_renameHandled) CommitRename();
        _renamingNoteId = null;
    }

    /// <summary>Refuses a blank title -- the tab strip's own half of the "revert to the
    /// previous value" requirement; NotesViewModel.RenameNote refuses one too, as a second
    /// line of defence, but this is what stops NoteRenamed from ever being raised with one
    /// in the first place.</summary>
    private void CommitRename()
    {
        if (_renamingNoteId is not { } id) return;
        string trimmed = _renameBox.Text.Trim();
        if (trimmed.Length == 0) return;
        NoteRenamed?.Invoke(id, trimmed);
    }
}
