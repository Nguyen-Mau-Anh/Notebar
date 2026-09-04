using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Input;
using Notebar.App.Editor;
using Notebar.App.Features.Linking;
using Notebar.App.Panel;
using Notebar.Core.Models;
using Notebar.Core.Repositories;
using Windows.Foundation;

namespace Notebar.App.Features.Notes;

/// <summary>Coordinates the tab strip, the one shared NoteEditorHost, the all-notes menu,
/// and (Task 15) the @ mention popover and the backlinks list. See NotesTab.xaml's own
/// remarks for the overall shape.</summary>
internal sealed partial class NotesTab : UserControl
{
    /// <summary>Every candidate the @ popover shows, note or task combined, most recently
    /// updated first -- bounded so a database with hundreds of notes never renders hundreds
    /// of rows into a 220pt-tall popover. Screen spec §4.2 says "scrolls beyond that
    /// [height]", not "shows everything"; AllNotesMenu has no such cap because its own list
    /// is the user's entire deliberate inventory, not a per-keystroke filter.</summary>
    private const int MaxMentionResults = 20;

    private NotesViewModel? _viewModel;
    private NoteEditorHost? _editor;
    private Flyout? _allNotesFlyout;
    private AllNotesMenu? _allNotesMenu;

    private INoteRepository? _noteRepository;
    private ITaskRepository? _taskRepository;
    private ILinkRepository? _linkRepository;

    private Flyout? _mentionFlyout;
    private MentionAutocomplete? _mentionAutocomplete;
    private bool _mentionOpen;
    // Set right before hiding _mentionFlyout for a selected candidate, so the Flyout's own
    // Closed handler (which otherwise tells the guest to clear its mention session -- see
    // its own remarks) does not race NoteEditorHost.InsertChipAsync's guest call and clear
    // mentionAnchor guest-side before insertMentionChip has had a chance to read it.
    private bool _mentionCommitting;

    internal NotesTab() => InitializeComponent();

    /// <summary>Wires everything up. Called once by RootPage.AttachController, which is the
    /// earliest point at which the note repositories and the app's one PanelController both
    /// exist.</summary>
    internal void Attach(
        INoteRepository noteRepository,
        IOpenTabRepository openTabRepository,
        IAttachmentRepository attachmentRepository,
        ITaskRepository taskRepository,
        ILinkRepository linkRepository,
        PanelController panelController)
    {
        _noteRepository = noteRepository;
        _taskRepository = taskRepository;
        _linkRepository = linkRepository;

        _viewModel = new NotesViewModel(noteRepository, openTabRepository);
        _viewModel.ActiveNoteChanged += OnActiveNoteChanged;
        _viewModel.TabsChanged += OnTabsChanged;

        TabStrip.Bind(_viewModel);
        TabStrip.NoteSelected += OnNoteSelected;
        TabStrip.NoteCloseRequested += OnNoteCloseRequested;
        TabStrip.NoteRenamed += OnNoteRenamed;

        _editor = new NoteEditorHost(noteRepository, attachmentRepository, linkRepository, panelController);
        _editor.ContentChanged += OnEditorContentChanged;
        // Task 13: FormattingBarControl.SetActiveStyles(EditorStyles) matches
        // StylesChanged's own Action<EditorStyles> signature directly, so this needs no
        // lambda wrapper -- editor.js's selectionchange handler is what actually drives it.
        _editor.StylesChanged += FormattingBarControl.SetActiveStyles;
        // Task 15: a note chip opens that note as a tab; a task chip has nowhere to go yet
        // (Features/Tasks/ is off limits to this task) -- see LinkNavigation's own remarks.
        _editor.ChipClicked += OnChipClicked;
        _editor.MentionUpdated += OnMentionUpdated;
        _editor.MentionKeyPressed += OnMentionKeyPressed;
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

        // Task 15's own overlay: the @ mention popover. Same "Opened/Closed cover every
        // dismissal path uniformly" pattern as _allNotesFlyout above -- a candidate click,
        // Enter/Tab, Escape (guest-side, which posts open:false and reaches Hide() via
        // OnMentionUpdated), and light-dismiss on a click elsewhere in the panel all raise
        // Closed the same way.
        _mentionAutocomplete = new MentionAutocomplete();
        _mentionAutocomplete.CandidateSelected += OnMentionCandidateSelected;
        _mentionFlyout = new Flyout { Content = _mentionAutocomplete, ShowMode = FlyoutShowMode.Transient };
        _mentionFlyout.Opened += (_, _) => panelController.HasOpenOverlay = true;
        _mentionFlyout.Closed += (_, _) =>
        {
            panelController.HasOpenOverlay = false;
            _mentionOpen = false;
            // Skipped when the close is a candidate being committed: InsertChipAsync is
            // about to make (or has just made) its own guest call that depends on
            // mentionAnchor still being set, and this would race it -- see
            // OnMentionCandidateSelected and _mentionCommitting's own remarks above.
            if (!_mentionCommitting) _ = _editor?.CancelMentionAsync();
            _mentionCommitting = false;
        };

        Backlinks.TargetSelected += OnBacklinkSelected;

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

        // A note's own backlinks can only change by some *other* note or task linking to
        // it, never by editing this one -- recomputing on every note switch is enough,
        // no need to redo it on every keystroke the way tab title/body updates are.
        Backlinks.Show(active is not null ? BuildBacklinks(active.Id) : []);
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

    // --- Task 15: linking (@ mention autocomplete, chip clicks, backlinks) ---

    /// <summary>Routes a clicked chip's target the same way OnBacklinkSelected below routes
    /// a backlink row -- product spec §6.4 deliverable 4's "same path a chip click uses" is
    /// mutual: both funnel through the identical open-note/request-task split. A URL this
    /// app never wrote (a foreign scheme, or a malformed notebar:// URL) parses to null and
    /// is silently ignored, mirroring LinkUrl.Parse's own contract.</summary>
    private void OnChipClicked(string url)
    {
        LinkTarget? target = LinkUrl.Parse(url);
        if (target is null) return;
        RouteLinkTarget(target.Value);
    }

    private void OnBacklinkSelected(MentionCandidate candidate) =>
        RouteLinkTarget(new LinkTarget(candidate.Type, candidate.Id));

    private void RouteLinkTarget(LinkTarget target)
    {
        if (target.Type == LinkEntityType.Note) _viewModel?.OpenNote(target.Id);
        else LinkNavigation.RequestTask(target.Id);
    }

    /// <summary>Reacts to the guest's live @ mention session state (see
    /// EditorMessage.Mention's own remarks) by showing, updating, or hiding the host-side
    /// popover -- the popover is only ever (re)positioned on the open transition, not on
    /// every query update while it's already showing, so it does not visibly jump as the
    /// candidate list's own height changes underneath it.</summary>
    private void OnMentionUpdated(MentionUpdate update)
    {
        if (_editor is null || _mentionFlyout is null || _mentionAutocomplete is null) return;

        if (!update.Open)
        {
            if (_mentionOpen) _mentionFlyout.Hide();
            return;
        }

        _mentionAutocomplete.SetCandidates(BuildMentionCandidates(update.Query));

        if (!_mentionOpen)
        {
            _mentionOpen = true;
            _mentionFlyout.ShowAt(_editor, new FlyoutShowOptions { Position = new Point(update.X, update.Y) });
        }
    }

    /// <summary>ArrowUp/ArrowDown/Enter/Tab, forwarded from the guest because the popover
    /// they drive is host-side XAML the guest cannot reach directly (see
    /// EditorMessage.MentionKey's own remarks). Ignored while no popover is actually
    /// open -- a key message racing a session that already closed guest-side.</summary>
    private void OnMentionKeyPressed(string key)
    {
        if (!_mentionOpen || _mentionAutocomplete is null) return;
        switch (key)
        {
            case "ArrowDown": _mentionAutocomplete.MoveSelection(1); break;
            case "ArrowUp": _mentionAutocomplete.MoveSelection(-1); break;
            case "Enter":
            case "Tab":
                _mentionAutocomplete.CommitSelection();
                break;
        }
    }

    private async void OnMentionCandidateSelected(MentionCandidate candidate)
    {
        if (_editor is null) return;
        // Set before Hide(), not after -- see _mentionCommitting's own remarks on the race
        // this avoids with the Flyout's Closed handler.
        _mentionCommitting = true;
        _mentionFlyout?.Hide();
        await _editor.InsertChipAsync(new LinkTarget(candidate.Type, candidate.Id), candidate.Title);
    }

    /// <summary>Every note/task whose title or detail matches query, most recently updated
    /// first, capped at MaxMentionResults and excluding the note currently open (linking a
    /// note to itself is never useful). A blank query (the popover's very first frame, right
    /// after typing "@") cannot go through INoteRepository.Search/ITaskRepository.Search --
    /// both are FTS5-backed and documented to return nothing for a blank query -- so that
    /// case lists the most recently updated notes/tasks instead, the same "most-recently-
    /// updated first" ordering AllNotesMenu already uses for its own no-filter list.</summary>
    private IReadOnlyList<MentionCandidate> BuildMentionCandidates(string query)
    {
        if (_noteRepository is null || _taskRepository is null) return [];

        IEnumerable<MentionCandidate> notes;
        IEnumerable<MentionCandidate> tasks;
        if (string.IsNullOrWhiteSpace(query))
        {
            notes = _noteRepository.Summaries()
                .Select(s => new MentionCandidate(LinkEntityType.Note, s.Id, s.Title, s.UpdatedAt));
            tasks = _taskRepository.All()
                .Select(t => new MentionCandidate(LinkEntityType.Task, t.Id, t.Title, t.UpdatedAt));
        }
        else
        {
            notes = _noteRepository.Search(query)
                .Select(n => new MentionCandidate(LinkEntityType.Note, n.Id, n.Title, n.UpdatedAt));
            tasks = _taskRepository.Search(query)
                .Select(t => new MentionCandidate(LinkEntityType.Task, t.Id, t.Title, t.UpdatedAt));
        }

        string? activeNoteId = _viewModel?.ActiveNoteId;
        return notes.Concat(tasks)
            .Where(c => c.Type != LinkEntityType.Note || c.Id != activeNoteId)
            .OrderByDescending(c => c.UpdatedAt)
            .Take(MaxMentionResults)
            .ToList();
    }

    /// <summary>Every note/task that links to noteId, resolved to a titled row -- one
    /// ILinkRepository.Incoming query, then a Fetch/lookup per backlink to get a title, the
    /// same "resolve a handful of rows, not a whole table" cost BuildMentionCandidates' own
    /// blank-query branch already pays. ITaskRepository has no single-id Fetch the way
    /// INoteRepository does, so a task backlink's title comes from a linear scan of All() --
    /// bounded by how many tasks exist, not by the query, and no worse than what
    /// TasksViewModel itself already does to look up a task by id.</summary>
    private IReadOnlyList<MentionCandidate> BuildBacklinks(string noteId)
    {
        if (_linkRepository is null) return [];

        IReadOnlyList<Link> incoming = _linkRepository.Incoming(new LinkTarget(LinkEntityType.Note, noteId));
        if (incoming.Count == 0) return [];

        // Fetched at most once, and only when at least one backlink actually needs it --
        // most notes have zero or a handful of backlinks, so this stays well short of the
        // "one query per row" cost ExistingTargets' own remarks warn against for tombstones.
        bool needsTasks = incoming.Any(link => link.SrcType == LinkEntityType.Task);
        IReadOnlyList<TaskItem> allTasks = needsTasks ? _taskRepository?.All() ?? [] : [];

        var rows = new List<MentionCandidate>(incoming.Count);
        foreach (Link link in incoming)
        {
            LinkTarget source = link.Source;
            if (source.Type == LinkEntityType.Note)
            {
                Note? note = _noteRepository?.Fetch(source.Id);
                if (note is not null) rows.Add(new MentionCandidate(LinkEntityType.Note, note.Id, note.Title, note.UpdatedAt));
            }
            else
            {
                TaskItem? task = allTasks.FirstOrDefault(t => t.Id == source.Id);
                if (task is not null) rows.Add(new MentionCandidate(LinkEntityType.Task, task.Id, task.Title, task.UpdatedAt));
            }
        }

        return rows.OrderByDescending(r => r.UpdatedAt).ToList();
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
