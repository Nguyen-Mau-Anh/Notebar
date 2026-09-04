using System.ComponentModel;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Notebar.App.Panel;
using Notebar.Core.Models;
using Notebar.Core.Panel;
using Notebar.Core.Repositories;

namespace Notebar.App.Features;

/// <summary>Hosts the rail plus the active tab's toolbar and body, and swaps to the collapsed
/// handle when the panel is collapsed.</summary>
/// <remarks>
/// The panel is drawn by one window for its whole life (screen spec §2: "there is no second
/// window") -- PanelController simply resizes that window between the collapsed handle's
/// rect and the expanded/maximized rect. This page mirrors that: which of ChromeRoot or
/// Handle is showing is decided purely from this page's own actual size on every
/// SizeChanged, never from a separate boolean someone has to remember to keep in sync with
/// whatever PanelController is doing.
/// </remarks>
internal sealed partial class RootPage : Page
{
    /// <summary>Margin above PanelTiming.HandleWidth used to classify the window's current
    /// size as collapsed. PanelGeometry.Collapsed is exactly HandleWidth wide, and every
    /// other rect this window is ever sized to -- the compact rail's own breakpoint
    /// included -- is far larger, so this only needs to be bigger than DPI-rounding noise,
    /// not tuned against any other real measurement.</summary>
    private const double CollapsedWidthMargin = 40;

    private PanelViewModel? _viewModel;

    internal RootPage()
    {
        InitializeComponent();
        SizeChanged += OnSizeChanged;
    }

    /// <summary>Called once by PanelWindow after both this page and the PanelController it
    /// needs exist. The controller cannot exist before the window does -- App.xaml.cs
    /// constructs PanelWindow first and PanelController second, wrapping the window it just
    /// built -- so it cannot be handed in through this page's own constructor. The note
    /// repositories are Task 12's, for NotesTabControl; taskRepository is Task 14's, for
    /// TasksTabControl; linkRepository is Task 15's, for NotesTabControl's mention
    /// popover/backlinks (NotesTabControl also needs taskRepository itself, to search tasks
    /// for the mention popover and resolve a task backlink's title). appStateRepository and
    /// diagnosticsRepository are Task 16's, for SettingsTabControl.</summary>
    internal void AttachController(
        PanelController panelController,
        INoteRepository noteRepository,
        IOpenTabRepository openTabRepository,
        IAttachmentRepository attachmentRepository,
        ITaskRepository taskRepository,
        ILinkRepository linkRepository,
        IAppStateRepository appStateRepository,
        IDiagnosticsRepository diagnosticsRepository)
    {
        _viewModel = new PanelViewModel(panelController);
        _viewModel.PropertyChanged += OnViewModelPropertyChanged;
        Rail.ViewModel = _viewModel;
        Handle.SetTab(_viewModel.Selection);
        UpdateActiveTab();

        NotesTabControl.Attach(noteRepository, openTabRepository, attachmentRepository, taskRepository, linkRepository, panelController);
        // _viewModel is also handed to TasksTabControl (not just panelController): a task
        // chip/backlink click, routed through LinkNavigation.TaskRequested (see
        // TasksTab.OnTaskRequested), needs to switch the rail's own selection to the Tasks
        // tab, not just open the task once there.
        TasksTabControl.Attach(taskRepository, panelController, _viewModel);
        // ApplyTheme (this page's own method, below) is the live-apply half of a theme
        // change -- SettingsTabControl persists through appStateRepository itself and calls
        // this to re-resolve every {ThemeResource} in the tree immediately, matching the
        // brief's "must switch live, not on next launch."
        SettingsTabControl.Attach(appStateRepository, diagnosticsRepository, ApplyTheme);

        // Task 12's data-loss fix: App.FlushPendingNoteSave is the seam Task 9
        // named but nothing could assign until a NoteEditorHost existed to
        // wire it to. App.Quit() awaits this before disposing anything or
        // exiting -- see App.QuitAsync.
        ((App)Application.Current).FlushPendingNoteSave = NotesTabControl.FlushPendingSaveAsync;
    }

    /// <summary>Sets RequestedTheme on this page -- the root of the whole chrome's visual
    /// tree (this Page is PanelWindow's direct Content, see PanelWindow.xaml) -- so every
    /// {ThemeResource} lookup underneath it re-resolves immediately. Called once at launch
    /// with the persisted value (App.xaml.cs, via PanelWindow.ApplyTheme) and again on every
    /// live change from Settings -> General.</summary>
    internal void ApplyTheme(Theme theme) => RequestedTheme = theme switch
    {
        Theme.Light => ElementTheme.Light,
        Theme.Dark => ElementTheme.Dark,
        _ => ElementTheme.Default,
    };

    /// <summary>Switches the rail's own selection. Used by PanelWindow.ShowSettingsTab
    /// (the tray menu's "Settings" entry) to land on a specific tab rather than whatever
    /// was last active.</summary>
    internal void SelectTab(AppTab tab)
    {
        if (_viewModel is not null) _viewModel.Selection = tab;
    }

    private void OnViewModelPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName != nameof(PanelViewModel.Selection)) return;
        UpdateActiveTab();
        if (_viewModel is not null) Handle.SetTab(_viewModel.Selection);
    }

    private void UpdateActiveTab()
    {
        AppTab selection = _viewModel?.Selection ?? AppTab.Notes;
        NotesTabRoot.Visibility = selection == AppTab.Notes ? Visibility.Visible : Visibility.Collapsed;
        TasksTabRoot.Visibility = selection == AppTab.Tasks ? Visibility.Visible : Visibility.Collapsed;
        SettingsTabRoot.Visibility = selection == AppTab.Settings ? Visibility.Visible : Visibility.Collapsed;

        // Data's facts (size on disk especially) can go stale between app launch and
        // whenever the user actually opens Settings, since the database keeps changing as
        // notes/tasks are written in the meantime -- refresh on every switch into this tab
        // rather than trusting Attach's one-time read at startup.
        if (selection == AppTab.Settings) SettingsTabControl.RefreshData();
    }

    /// <summary>The only place expanded-vs-collapsed is decided -- see the class
    /// remarks.</summary>
    private void OnSizeChanged(object sender, SizeChangedEventArgs e)
    {
        bool isCollapsed = e.NewSize.Width <= PanelTiming.HandleWidth + CollapsedWidthMargin;
        ChromeRoot.Visibility = isCollapsed ? Visibility.Collapsed : Visibility.Visible;
        Handle.Visibility = isCollapsed ? Visibility.Visible : Visibility.Collapsed;

        if (!isCollapsed)
        {
            bool isCompact = e.NewSize.Width < PanelTiming.PanelWidth;
            Rail.SetCompact(isCompact);
        }
    }
}
