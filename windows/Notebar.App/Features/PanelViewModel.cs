using System.ComponentModel;
using System.Runtime.CompilerServices;
using Notebar.App.Panel;
using Notebar.Core.Panel;

namespace Notebar.App.Features;

/// <summary>The chrome state TabRail, TabToolbar, and the collapsed handle bind to: which tab
/// is selected, and the pin/maximize toggles. Deliberately thin -- per-tab content (open
/// notes, the task board, ...) gets its own view model in the tasks that build those tabs;
/// this is only what the shell itself needs.</summary>
/// <remarks>
/// IsPinned and IsMaximized push their new value into PanelController from their own
/// SETTERS, never from a click handler downstream. The macOS pin toggle shipped one click
/// behind because the observation of the pinned flag fired before the mutation reached
/// PanelController -- reading an old value, flipping a separate bool, and only later having
/// something else notice and forward it, three steps with room for a stale read in between.
/// Routing every mutation through the property setter collapses that to one step: whatever
/// sets IsPinned is what PanelController sees, synchronously, in the same call. TabRail's
/// pin toggle honours this by forwarding its own already-committed IsChecked value into this
/// setter, rather than computing "the opposite of the old value" itself -- see TabRail.
/// </remarks>
internal sealed class PanelViewModel : INotifyPropertyChanged
{
    private readonly PanelController _panelController;
    private AppTab _selection = AppTab.Notes;
    private bool _isPinned;
    private bool _isMaximized;

    public event PropertyChangedEventHandler? PropertyChanged;

    internal PanelViewModel(PanelController panelController)
    {
        _panelController = panelController;
        _isPinned = panelController.IsPinned;
        _isMaximized = panelController.IsMaximized;
    }

    internal AppTab Selection
    {
        get => _selection;
        set
        {
            if (_selection == value) return;
            _selection = value;
            OnPropertyChanged();
        }
    }

    /// <summary>The only path that writes PanelController.IsPinned -- see the class
    /// remarks.</summary>
    internal bool IsPinned
    {
        get => _isPinned;
        set
        {
            if (_isPinned == value) return;
            _isPinned = value;
            _panelController.IsPinned = value;
            OnPropertyChanged();
        }
    }

    /// <summary>Flips PanelController.IsMaximized and re-applies the window frame
    /// immediately (PanelController.ReapplyFrame), rather than leaving the new size to be
    /// picked up whenever the cursor next moves and PanelController.Send happens to
    /// run.</summary>
    internal bool IsMaximized
    {
        get => _isMaximized;
        set
        {
            if (_isMaximized == value) return;
            _isMaximized = value;
            _panelController.IsMaximized = value;
            _panelController.ReapplyFrame();
            OnPropertyChanged();
        }
    }

    /// <summary>The rail's bottom collapse control calls this. Sends
    /// PanelEvent.ToggleRequested, the same event the tray icon and the global hotkey use,
    /// so collapsing from inside the panel goes through the identical state-machine path as
    /// every other way to dismiss it -- the point of an in-panel collapse control is
    /// dismissing the panel without moving the cursor off it, not a bespoke path to
    /// Hidden.</summary>
    internal void RequestCollapse() => _panelController.Send(PanelEvent.ToggleRequested);

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
}
