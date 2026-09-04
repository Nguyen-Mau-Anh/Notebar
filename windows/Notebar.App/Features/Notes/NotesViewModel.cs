using Notebar.Core.Models;
using Notebar.Core.Repositories;

namespace Notebar.App.Features.Notes;

/// <summary>Open-notes state for the Notes tab: which notes have tabs, which tab is active,
/// and the create/open/select/close/rename actions that mutate them.</summary>
/// <remarks>
/// Persists the open-tab strip through IOpenTabRepository.ReplaceAll on every open, close,
/// and select -- never per keystroke (task brief). The 400ms autosave debounce is a
/// completely separate path owned by NoteEditorHost; this class never writes a note's body
/// itself, only its title and the strip's own shape.
/// </remarks>
internal sealed class NotesViewModel
{
    private readonly INoteRepository _notes;
    private readonly IOpenTabRepository _openTabs;
    private readonly List<Note> _openNotes = [];

    /// <summary>Every open note, in tab-strip order. A plain read-only view, not an
    /// ObservableCollection -- nothing here binds to it directly; NoteTabStrip re-renders
    /// from TabsChanged/ActiveNoteChanged instead, the same imperative-rebuild pattern
    /// TabRail and RootPage already use throughout this codebase.</summary>
    internal IReadOnlyList<Note> OpenNotes => _openNotes;

    internal string? ActiveNoteId { get; private set; }

    internal Note? ActiveNote => ActiveNoteId is { } id ? _openNotes.Find(n => n.Id == id) : null;

    /// <summary>Raised whenever ActiveNoteId changes, including to null when the last tab
    /// closes.</summary>
    internal event Action? ActiveNoteChanged;

    /// <summary>Raised whenever the open-tab list itself changes shape or a tab's title
    /// changes (create, open, close, rename) -- not on every keystroke, which never reaches
    /// this class at all.</summary>
    internal event Action? TabsChanged;

    internal NotesViewModel(INoteRepository notes, IOpenTabRepository openTabs)
    {
        _notes = notes;
        _openTabs = openTabs;
    }

    /// <summary>Loads the persisted strip. Call once, before anything else. A tab whose note
    /// no longer exists -- should not normally happen, since deletion always goes through
    /// this class, but a hand-edited or otherwise corrupted database is not this method's job
    /// to trust -- is silently dropped rather than surfaced as a broken tab; the trailing
    /// Persist() then corrects the stored strip to match what was actually loaded.</summary>
    internal void LoadPersisted()
    {
        string? active = null;
        foreach (OpenTab tab in _openTabs.All())
        {
            if (tab.Kind != OpenTab.NoteKind) continue;
            Note? note = _notes.Fetch(tab.RefId);
            if (note is null) continue;
            _openNotes.Add(note);
            if (tab.IsActive) active = note.Id;
        }
        ActiveNoteId = active ?? (_openNotes.Count > 0 ? _openNotes[0].Id : null);
        Persist();
    }

    internal void CreateNote()
    {
        Note note = _notes.Create();
        _openNotes.Add(note);
        SetActive(note.Id);
        TabsChanged?.Invoke();
        Persist();
    }

    /// <summary>Opens a note that may or may not already have a tab -- the all-notes menu's
    /// row click. Never reads the note's body itself: the menu built its list from
    /// Summaries(), so the full Note this needs comes from Fetch(id) here, the one place in
    /// this flow allowed to read it.</summary>
    internal void OpenNote(string id)
    {
        if (_openNotes.Exists(n => n.Id == id))
        {
            SetActive(id);
            Persist();
            return;
        }

        Note? note = _notes.Fetch(id);
        if (note is null) return;
        _openNotes.Add(note);
        SetActive(id);
        TabsChanged?.Invoke();
        Persist();
    }

    internal void SelectNote(string id)
    {
        if (id == ActiveNoteId) return;
        if (!_openNotes.Exists(n => n.Id == id)) return;
        SetActive(id);
        Persist();
    }

    /// <summary>Closes a tab. Per the macOS defect this must never silently destroy content:
    /// Note.IsEmptyAndUntitled -- checked against this class's own in-memory copy of the
    /// note, which UpdateNoteContent keeps current as NoteEditorHost saves -- is the only
    /// test for whether the underlying row is deleted along with the tab. The caller (see
    /// NotesTab.OnNoteCloseRequested) is responsible for flushing the editor's pending save
    /// first when the tab being closed is the active one, so this in-memory copy is never
    /// stale at the moment this runs.</summary>
    internal void CloseNote(string id)
    {
        int index = _openNotes.FindIndex(n => n.Id == id);
        if (index < 0) return;

        Note note = _openNotes[index];
        _openNotes.RemoveAt(index);
        if (note.IsEmptyAndUntitled) _notes.Delete(id);

        if (ActiveNoteId == id)
        {
            Note? next = _openNotes.Count == 0 ? null : _openNotes[Math.Min(index, _openNotes.Count - 1)];
            SetActive(next?.Id);
        }

        TabsChanged?.Invoke();
        Persist();
    }

    /// <summary>Commits a rename. Refuses a blank title, in addition to (not instead of) the
    /// tab strip's own refusal to ever call this with one -- see NoteTabStrip's rename
    /// commit.</summary>
    internal void RenameNote(string id, string title)
    {
        string trimmed = title.Trim();
        if (trimmed.Length == 0) return;

        int index = _openNotes.FindIndex(n => n.Id == id);
        if (index < 0) return;

        Note renamed = _openNotes[index] with { Title = trimmed };
        _notes.Update(renamed);
        _openNotes[index] = renamed;
        TabsChanged?.Invoke();
    }

    /// <summary>Keeps this class's in-memory copy of a note current with what
    /// NoteEditorHost has just persisted, so a later CloseNote sees the real BodyPlain
    /// rather than whatever it was when the tab was opened.</summary>
    internal void UpdateNoteContent(string id, string bodyHtml, string bodyPlain)
    {
        int index = _openNotes.FindIndex(n => n.Id == id);
        if (index < 0) return;
        _openNotes[index] = _openNotes[index] with { BodyHtml = bodyHtml, BodyPlain = bodyPlain };
    }

    /// <summary>Every note, most recently updated first -- the all-notes menu's list. Built
    /// from Summaries(), never All(): drawing this list must never pay for reading every
    /// note's body.</summary>
    internal IReadOnlyList<NoteSummary> AllNotesByRecency() =>
        _notes.Summaries().OrderByDescending(s => s.UpdatedAt).ToList();

    internal bool IsOpen(string id) => _openNotes.Exists(n => n.Id == id);

    private void SetActive(string? id)
    {
        if (ActiveNoteId == id) return;
        ActiveNoteId = id;
        ActiveNoteChanged?.Invoke();
    }

    private void Persist()
    {
        var tabs = new List<OpenTab>(_openNotes.Count);
        for (int i = 0; i < _openNotes.Count; i++)
        {
            Note note = _openNotes[i];
            tabs.Add(new OpenTab(note.Id, OpenTab.NoteKind, note.Id, i, note.Id == ActiveNoteId));
        }
        _openTabs.ReplaceAll(tabs);
    }
}
