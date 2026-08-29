import Foundation

/// Storage for `Note`, defined here so `NotebarStore`'s GRDB implementation
/// has a contract to satisfy without this module ever importing GRDB —
/// GRDB targets Apple platforms and Linux, not Windows, and `NotebarCore`
/// must recompile under Swift for Windows in M5 (spec §3, rule 1). A future
/// Windows port swaps in a different implementation of this protocol; call
/// sites never change.
///
/// Synchronous and throwing, not `async`, deliberately: the underlying store
/// is a local SQLite file accessed through GRDB's `DatabaseQueue`, which is
/// itself a synchronous, serializing API — wrapping every call in `async`
/// would add `Task`/actor-isolation overhead for what is a sub-millisecond
/// local operation, and would pull Swift Concurrency's stricter checking
/// into a package that deliberately stays in Swift 5 language mode (spec §2)
/// to keep the AppKit-unfamiliar author unblocked. Callers that must not
/// block their thread (e.g. `PanelViewModel` saving on a debounce) dispatch
/// to a background queue themselves; the protocol stays simple either way.
public protocol NoteRepository {
    /// Every note, ordered by `sortOrder` ascending.
    func all() throws -> [Note]

    /// Every note's lightweight summary — id, title, `updatedAt`, nothing
    /// else — ordered by `sortOrder` ascending same as `all()` (spec §6.2c
    /// deliverable 4). Never selects `body_rtf`, so a caller that only needs
    /// to render a list of names (the all-notes menu) never pays for
    /// reading every note's body off disk. Fetching the note actually being
    /// opened still goes through `fetch(id:)` or `all()`.
    func summaries() throws -> [NoteSummary]

    /// Fetches a single note by id, or `nil` if it doesn't exist. The
    /// all-notes menu's row action uses this to open a note it only has a
    /// `NoteSummary` for, so opening one note never reads every other note's
    /// body along the way (spec §6.2c deliverable 4).
    func fetch(id: Note.ID) throws -> Note?

    /// Creates a new note, appended after the current last note (or first,
    /// if the store is empty), and persists it immediately.
    @discardableResult
    func create() throws -> Note

    /// Persists every mutable field of an existing note and stamps
    /// `updatedAt`. The row must already exist; unknown ids throw.
    func update(_ note: Note) throws

    /// Deletes a note. A no-op if `id` does not exist.
    func delete(id: Note.ID) throws

    /// Moves the note with `id` to a fractional `sortOrder` strictly between
    /// `before` and `after`'s current positions (spec §5 "why sort_order
    /// REAL"), so a reorder is one row update rather than a renumbering
    /// pass. Pass `nil` for either bound to move to that end of the list.
    @discardableResult
    func reorder(id: Note.ID, before: Note.ID?, after: Note.ID?) throws -> Note

    /// Full-text search over title and body via the `note_fts` index
    /// (`NoteSchema`), most relevant match first. Returns an empty array for
    /// a blank query.
    func search(_ query: String) throws -> [Note]
}
