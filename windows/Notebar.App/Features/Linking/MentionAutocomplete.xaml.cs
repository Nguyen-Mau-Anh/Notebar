using System.Collections.ObjectModel;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Notebar.App.Features.Linking;

/// <summary>Code-behind for the @ mention popover's content. See MentionAutocomplete.xaml's
/// own remarks -- this only renders rows and raises CandidateSelected; NotesTab owns the
/// Flyout, positions it near the caret, and sets PanelController.HasOpenOverlay while it is
/// open.</summary>
internal sealed partial class MentionAutocomplete : UserControl
{
    private readonly ObservableCollection<MentionRowVm> _rows = [];
    private int _highlightedIndex = -1;

    internal event Action<MentionCandidate>? CandidateSelected;

    internal MentionAutocomplete()
    {
        InitializeComponent();
        RowsList.ItemsSource = _rows;
    }

    /// <summary>Rebuilds the row list from scratch and selects the first row by default, so
    /// Enter/Tab commits something the instant a popover with any matches opens. Called by
    /// NotesTab every time the guest reports the query changing, not only when the popover
    /// first opens.</summary>
    internal void SetCandidates(IReadOnlyList<MentionCandidate> candidates)
    {
        _rows.Clear();
        foreach (MentionCandidate candidate in candidates) _rows.Add(new MentionRowVm(candidate));
        _highlightedIndex = _rows.Count > 0 ? 0 : -1;
        ApplyHighlight();

        bool empty = _rows.Count == 0;
        EmptyLabel.Visibility = empty ? Visibility.Visible : Visibility.Collapsed;
        ListScroller.Visibility = empty ? Visibility.Collapsed : Visibility.Visible;
    }

    /// <summary>Moves the keyboard-selected row by delta, wrapping around both ends -- the
    /// guest forwards ArrowUp/ArrowDown as a "mentionKey" message (it cannot handle them
    /// itself: the popover is host-side XAML) rather than letting them move the caret in the
    /// document while a mention session is open.</summary>
    internal void MoveSelection(int delta)
    {
        if (_rows.Count == 0) return;
        _highlightedIndex = ((_highlightedIndex + delta) % _rows.Count + _rows.Count) % _rows.Count;
        ApplyHighlight();
    }

    /// <summary>Selects whichever row is currently highlighted -- Enter/Tab's effect, and a
    /// no-op when there is nothing to select (an empty popover).</summary>
    internal void CommitSelection()
    {
        if (_highlightedIndex < 0 || _highlightedIndex >= _rows.Count) return;
        CandidateSelected?.Invoke(_rows[_highlightedIndex].Candidate);
    }

    private void ApplyHighlight()
    {
        for (int i = 0; i < _rows.Count; i++) _rows[i].IsHighlighted = i == _highlightedIndex;
    }

    private void OnRowClick(object sender, RoutedEventArgs e)
    {
        if (((FrameworkElement)sender).DataContext is MentionRowVm row)
            CandidateSelected?.Invoke(row.Candidate);
    }
}
