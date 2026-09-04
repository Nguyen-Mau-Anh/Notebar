using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Notebar.App.Panel;
using Notebar.Core.Models;
using Notebar.Core.Repositories;

namespace Notebar.App.Features.Notes;

/// <summary>Coordinates the tab strip, the one shared NoteEditorHost, and the all-notes
/// menu. See NotesTab.xaml's own remarks for the overall shape.</summary>
internal sealed partial class NotesTab : UserControl
{
    private NotesViewModel? _viewModel;
    private NoteEditorHost? _editor;
    private Flyout? _allNotesFlyout;
    private AllNotesMenu? _allNotesMenu;

    internal NotesTab() => InitializeComponent();

    /// <summary>Wires everything up. Called once by RootPage.AttachController, which is the
    /// earliest point at which the note repositories and the app's one PanelController both
    /// exist.</summary>
    internal void Attach(
        INoteRepository noteRepository,
        IOpenTabRepository openTabRepository,
        IAttachmentRepository attachmentRepository,
        PanelController panelController)
    {
        _viewModel = new NotesViewModel(noteRepository, openTabRepository);
        _viewModel.ActiveNoteChanged += OnActiveNoteChanged;
        _viewModel.TabsChanged += OnTabsChanged;

        TabStrip.Bind(_viewModel);
        TabStrip.NoteSelected += OnNoteSelected;
        TabStrip.NoteCloseRequested += OnNoteCloseRequested;
        TabStrip.NoteRenamed += OnNoteRenamed;

        _editor = new NoteEditorHost(noteRepository, attachmentRepository, panelController);
        _editor.ContentChanged += OnEditorContentChanged;
        // Task 13: FormattingBarControl.SetActiveStyles(EditorStyles) matches
        // StylesChanged's own Action<EditorStyles> signature directly, so this needs no
        // lambda wrapper -- editor.js's selectionchange handler is what actually drives it.
        _editor.StylesChanged += FormattingBarControl.SetActiveStyles;
        EditorSlot.Children.Add(_editor);

        // The seven document.execCommand buttons all funnel through ExecCommandAsync; the
        // checklist button alone has no execCommand equivalent (see FormattingBar's own
        // remarks), so it goes through InsertHtmlAsync with the identical HTML instead.
        // Fire-and-forget on both -- same as every other _editor.*Async call this class
        // makes (OnNewNoteClick, OnActiveNoteChanged), none of which need to block the UI
        // thread on a WebView2 round trip.
        FormattingBarControl.ExecRequested += (command, value) => _ = _editor?.ExecCommandAsync(command, value);
        FormattingBarControl.ChecklistRequested += () => _ = _editor?.InsertHtmlAsync(FormattingBar.ChecklistHtml);

        // The Notes tab collapsing must not lose a save still waiting out its 400ms
        // debounce, same as switching tabs (NoteEditorHost.LoadAsync already flushes on
        // every switch) and quitting (App.QuitAsync awaits App.FlushPendingNoteSave, which
        // RootPage.AttachController points at FlushPendingSaveAsync below). Fire-and-forget
        // here is fine: collapsing does not need to block on a save completing, and
        // FlushPendingSaveAsync already swallows its own exceptions.
        panelController.PanelHidden += () => _ = FlushPendingSaveAsync();

        _allNotesMenu = new AllNotesMenu();
        _allNotesMenu.NoteSelected += OnAllNotesNoteSelected;
        _allNotesFlyout = new Flyout { Content = _allNotesMenu };
        // The first real overlay in the app (see PanelController.HasOpenOverlay's remarks
        // on PanelMachine treating it as a hard invariant). Opened/Closed cover every
        // dismissal path uniformly -- row selection, click-away, and Escape all raise
        // Closed the same way, which is exactly the "however it closes" guarantee the
        // panel's collapse policy needs.
        _allNotesFlyout.Opened += (_, _) => panelController.HasOpenOverlay = true;
        _allNotesFlyout.Closed += (_, _) => panelController.HasOpenOverlay = false;

        _viewModel.LoadPersisted();
        UpdateBody();
    }

    /// <summary>The flush seam App.xaml.cs's Quit() awaits. Never null once Attach has run;
    /// Task.CompletedTask before that (there is nothing to flush) or after this control is
    /// somehow torn down without a replacement having taken over the seam.</summary>
    internal Task FlushPendingSaveAsync() => _editor?.FlushPendingSaveAsync() ?? Task.CompletedTask;

    private async void OnActiveNoteChanged()
    {
        UpdateBody();
        Note? active = _viewModel?.ActiveNote;
        if (active is not null && _editor is not null)
            await _editor.LoadAsync(active);
    }

    private void OnTabsChanged() => UpdateBody();

    private void OnNoteSelected(string id) => _viewModel?.SelectNote(id);

    /// <summary>Flushes the active note's pending debounced save before evaluating whether
    /// closing it should delete it. Without this, text typed inside the 400ms autosave
    /// window and closed immediately would still read as IsEmptyAndUntitled against
    /// NotesViewModel's stale in-memory copy and be deleted outright -- exactly the
    /// data-loss defect the close-deletes-empty-notes behaviour exists to avoid triggering
    /// on real content. A background tab has no pending save to flush at all (only the
    /// active note is ever loaded into the one shared editor), so this only does anything
    /// when the tab being closed is the active one.</summary>
    private async void OnNoteCloseRequested(string id)
    {
        if (_viewModel is null) return;
        if (id == _viewModel.ActiveNoteId && _editor is not null)
            await _editor.FlushPendingSaveAsync();
        _viewModel.CloseNote(id);
    }

    private void OnNoteRenamed(string id, string title) => _viewModel?.RenameNote(id, title);

    private void OnEditorContentChanged(string id, string html, string plain) =>
        _viewModel?.UpdateNoteContent(id, html, plain);

    private void OnAllNotesNoteSelected(string id)
    {
        _allNotesFlyout?.Hide();
        _viewModel?.OpenNote(id);
    }

    private void UpdateBody()
    {
        bool hasActive = _viewModel?.ActiveNote is not null;
        EmptyState.Visibility = hasActive ? Visibility.Collapsed : Visibility.Visible;
        EditorSlot.Visibility = hasActive ? Visibility.Visible : Visibility.Collapsed;
        // §4.2 / FormattingBarView.swift: "Visible only while a note is open" -- same
        // condition as EditorSlot above, since there is never a note-less state where the
        // formatting bar has anything to format.
        FormattingBarControl.Visibility = hasActive ? Visibility.Visible : Visibility.Collapsed;
    }

    private void OnNewNoteClick(object sender, RoutedEventArgs e)
    {
        // Screen spec §4.1: a new note gets text-input focus immediately. Only here, not on
        // every OnActiveNoteChanged -- see NoteEditorHost.FocusEditor's own remarks on why
        // stealing focus on every tab switch (including ones driven by hover, not a click)
        // would undercut ShowWithoutActivating's whole point.
        _viewModel?.CreateNote();
        _editor?.FocusEditor();
    }

    private void OnAllNotesClick(object sender, RoutedEventArgs e)
    {
        if (_viewModel is null || _allNotesFlyout is null || _allNotesMenu is null) return;
        _allNotesMenu.Load(_viewModel);
        _allNotesFlyout.ShowAt(AllNotesButton);
    }

    // --- Toolbar action button hover (screen spec §2: "stepping to accent on hover with a
    // radius.sm background at accent 8%"). Moved from RootPage's placeholder -- see
    // RootPage.xaml.cs's own remarks. Every colour here is a static {ThemeResource ...}
    // reference in NotesTab.xaml; this only ever toggles which pre-declared element is
    // visible, never assigns a brush from code. ---

    private void OnNewNotePointerEntered(object sender, PointerRoutedEventArgs e) => SetActionHover(NewNoteHoverBg, NewNoteIconOff, NewNoteIconOn, true);
    private void OnNewNotePointerExited(object sender, PointerRoutedEventArgs e) => SetActionHover(NewNoteHoverBg, NewNoteIconOff, NewNoteIconOn, false);

    private void OnAllNotesPointerEntered(object sender, PointerRoutedEventArgs e) => SetActionHover(AllNotesHoverBg, AllNotesIconOff, AllNotesIconOn, true);
    private void OnAllNotesPointerExited(object sender, PointerRoutedEventArgs e) => SetActionHover(AllNotesHoverBg, AllNotesIconOff, AllNotesIconOn, false);

    private static void SetActionHover(Border hoverBg, FontIcon iconOff, FontIcon iconOn, bool isHovering)
    {
        hoverBg.Visibility = isHovering ? Visibility.Visible : Visibility.Collapsed;
        iconOff.Visibility = isHovering ? Visibility.Collapsed : Visibility.Visible;
        iconOn.Visibility = isHovering ? Visibility.Visible : Visibility.Collapsed;
    }
}
