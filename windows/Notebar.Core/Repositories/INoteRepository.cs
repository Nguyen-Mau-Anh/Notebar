using Notebar.Core.Models;

namespace Notebar.Core.Repositories;

/// <summary>Storage for Note, defined here so the store's SQLite implementation
/// has a contract to satisfy without the core ever referencing a database
/// package.</summary>
/// <remarks>
/// Synchronous rather than async, deliberately: the underlying store is a local
/// SQLite file behind a single connection, and every call is a sub-millisecond
/// local operation. Wrapping them in Task would add scheduling overhead for
/// nothing. Callers that must not block the UI thread — the editor's debounced
/// save — dispatch to a background thread themselves.
/// </remarks>
public interface INoteRepository
{
    /// <summary>Every note, ordered by SortOrder ascending.</summary>
    IReadOnlyList<Note> All();

    /// <summary>Every note's lightweight summary — id, title, UpdatedAt, nothing
    /// else — in the same order as All(). Never selects body_html, so rendering
    /// the all-notes menu never pays for reading every note's body.</summary>
    IReadOnlyList<NoteSummary> Summaries();

    /// <summary>A single note by id, or null if it does not exist.</summary>
    Note? Fetch(string id);

    /// <summary>Creates a note appended after the current last one (or first, if
    /// the store is empty) and persists it immediately.</summary>
    Note Create();

    /// <summary>Persists every mutable field of an existing note and stamps
    /// UpdatedAt. The row must already exist; unknown ids throw.</summary>
    void Update(Note note);

    /// <summary>Deletes a note. A no-op if id does not exist.</summary>
    void Delete(string id);

    /// <summary>Moves the note to a fractional SortOrder strictly between the two
    /// named neighbours, so a reorder is one row update rather than a renumbering
    /// pass. Pass null for either bound to move to that end of the list.</summary>
    Note Reorder(string id, string? beforeId, string? afterId);

    /// <summary>Full-text search over title and body via note_fts, most relevant
    /// first. Empty for a blank query.</summary>
    IReadOnlyList<Note> Search(string query);
}
