using System.ComponentModel;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Notebar.App.Panel;
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

    /// <summary>Raised by the Tasks toolbar's + button. Unwired for now -- Task 14 owns the
    /// task repository plumbing this needs.</summary>
    internal event RoutedEventHandler? NewTaskRequested;

    internal RootPage()
    {
        InitializeComponent();
        SizeChanged += OnSizeChanged;
    }

    /// <summary>Called once by PanelWindow after both this page and the PanelController it
    /// needs exist. The controller cannot exist before the window does -- App.xaml.cs
    /// constructs PanelWindow first and PanelController second, wrapping the window it just
    /// built -- so it cannot be handed in through this page's own constructor. The three
    /// repositories are Task 12's -- NotesTabControl is the only thing that needs them.</summary>
    internal void AttachController(
        PanelController panelController,
        INoteRepository noteRepository,
        IOpenTabRepository openTabRepository,
        IAttachmentRepository attachmentRepository)
    {
        _viewModel = new PanelViewModel(panelController);
        _viewModel.PropertyChanged += OnViewModelPropertyChanged;
        Rail.ViewModel = _viewModel;
        Handle.SetTab(_viewModel.Selection);
        UpdateActiveTab();

        NotesTabControl.Attach(noteRepository, openTabRepository, attachmentRepository, panelController);

        // Task 12's data-loss fix: App.FlushPendingNoteSave is the seam Task 9
        // named but nothing could assign until a NoteEditorHost existed to
        // wire it to. App.Quit() awaits this before disposing anything or
        // exiting -- see App.QuitAsync.
        ((App)Application.Current).FlushPendingNoteSave = NotesTabControl.FlushPendingSaveAsync;
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

    private void OnNewTaskClick(object sender, RoutedEventArgs e) => NewTaskRequested?.Invoke(this, e);

    // --- Toolbar action button hover (screen spec §2: "stepping to accent on hover with a
    // radius.sm background at accent 8%"). Every colour here is a static {ThemeResource ...}
    // reference in RootPage.xaml; this only ever toggles which pre-declared element is
    // visible, never assigns a brush from code. The Notes toolbar's own +/all-notes buttons
    // moved to NotesTab (Task 12) along with this same pattern -- see NotesTab.xaml.cs.

    private void OnNewTaskPointerEntered(object sender, PointerRoutedEventArgs e) => SetActionHover(NewTaskHoverBg, NewTaskIconOff, NewTaskIconOn, true);
    private void OnNewTaskPointerExited(object sender, PointerRoutedEventArgs e) => SetActionHover(NewTaskHoverBg, NewTaskIconOff, NewTaskIconOn, false);

    private static void SetActionHover(Border hoverBg, FontIcon iconOff, FontIcon iconOn, bool isHovering)
    {
        hoverBg.Visibility = isHovering ? Visibility.Visible : Visibility.Collapsed;
        iconOff.Visibility = isHovering ? Visibility.Collapsed : Visibility.Visible;
        iconOn.Visibility = isHovering ? Visibility.Visible : Visibility.Collapsed;
    }
}
