using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Notebar.App.Features.Linking;

/// <summary>Code-behind for the backlinks list. See BacklinksSection.xaml's own remarks --
/// this only renders rows NotesTab hands it and raises TargetSelected; NotesTab owns
/// resolving ILinkRepository.Incoming into titled rows and what happens when one is
/// clicked (the same open-note/open-task routing a chip click uses, per product spec §6.4
/// deliverable 4's "same path a chip click uses").</summary>
internal sealed partial class BacklinksSection : UserControl
{
    internal event Action<MentionCandidate>? TargetSelected;

    internal BacklinksSection() => InitializeComponent();

    /// <summary>Renders the given backlink rows, or hides the whole section when there are
    /// none. Called by NotesTab whenever the active note changes -- a note's own backlinks
    /// can only change by some *other* note or task linking to it, never by editing this
    /// one, so there is nothing to recompute on every keystroke.</summary>
    internal void Show(IReadOnlyList<MentionCandidate> backlinks)
    {
        RowsList.ItemsSource = backlinks;
        Root.Visibility = backlinks.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
    }

    private void OnRowClick(object sender, RoutedEventArgs e)
    {
        if (((FrameworkElement)sender).DataContext is MentionCandidate candidate)
            TargetSelected?.Invoke(candidate);
    }
}
