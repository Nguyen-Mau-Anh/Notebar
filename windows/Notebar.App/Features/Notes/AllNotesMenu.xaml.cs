using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Notebar.Core.Models;

namespace Notebar.App.Features.Notes;

/// <summary>Code-behind for the all-notes menu content. See AllNotesMenu.xaml's own
/// remarks -- this only renders rows and raises NoteSelected; NotesTab owns the Flyout and
/// the overlay flag.</summary>
internal sealed partial class AllNotesMenu : UserControl
{
    internal event Action<string>? NoteSelected;

    internal AllNotesMenu() => InitializeComponent();

    /// <summary>Rebuilds the row list. Called every time NotesTab is about to show this
    /// menu's Flyout, not once at construction -- the set of notes, their titles, and which
    /// ones are open can all have changed since the last time it was shown.</summary>
    internal void Load(NotesViewModel viewModel)
    {
        IReadOnlyList<NoteSummary> summaries = viewModel.AllNotesByRecency();
        var rows = summaries
            .Select(s => new AllNotesRowItem(s.Id, s.DisplayTitle, RelativeTime.Format(s.UpdatedAt), viewModel.IsOpen(s.Id)))
            .ToList();

        RowsList.ItemsSource = rows;

        bool empty = rows.Count == 0;
        EmptyLabel.Visibility = empty ? Visibility.Visible : Visibility.Collapsed;
        ListScroller.Visibility = empty ? Visibility.Collapsed : Visibility.Visible;
    }

    private void OnRowClick(object sender, RoutedEventArgs e)
    {
        if (((FrameworkElement)sender).DataContext is AllNotesRowItem row)
            NoteSelected?.Invoke(row.Id);
    }
}
