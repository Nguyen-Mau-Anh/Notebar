using System.ComponentModel;
using Notebar.App.Features.Notes;

namespace Notebar.App.Features.Linking;

/// <summary>A per-render row for MentionAutocomplete's list: a MentionCandidate plus the one
/// fact the popover adds that AllNotesRowItem's equivalent doesn't need -- whether this row
/// is the keyboard-selected one (screen spec §4.2: "the keyboard-selected row gets accent
/// 12% background with a 2px accent left border"). A class with INotifyPropertyChanged, not
/// a record like MentionCandidate/AllNotesRowItem: MoveSelection toggles IsHighlighted on
/// exactly two rows (the old and new selection) in place, and x:Bind's one-way binding needs
/// a change notification to repaint just those two rows rather than MentionAutocomplete
/// rebuilding its whole ItemsSource on every arrow key.</summary>
internal sealed class MentionRowVm(MentionCandidate candidate) : INotifyPropertyChanged
{
    private bool _isHighlighted;

    internal MentionCandidate Candidate { get; } = candidate;
    internal string DisplayTitle => Candidate.DisplayTitle;
    internal string TypeGlyph => Candidate.TypeGlyph;
    internal string RelativeTime => Notebar.App.Features.Notes.RelativeTime.Format(Candidate.UpdatedAt);

    internal bool IsHighlighted
    {
        get => _isHighlighted;
        set
        {
            if (_isHighlighted == value) return;
            _isHighlighted = value;
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(IsHighlighted)));
        }
    }

    public event PropertyChangedEventHandler? PropertyChanged;
}
