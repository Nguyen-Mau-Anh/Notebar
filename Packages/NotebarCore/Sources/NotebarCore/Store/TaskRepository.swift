import Foundation

/// Storage for `TaskItem` and its `BoardColumn`s, defined here so
/// `NotebarStore`'s GRDB implementation has a contract to satisfy without
/// this module ever importing GRDB — see `NoteRepository` for why, and why
/// this is synchronous rather than `async`.
public protocol TaskRepository {
    /// Every board column, ordered by `sortOrder` ascending. v1 seeds
    /// exactly the three columns spec §6.3a's board renders — Queue
    /// (`backlogKind`), Working (`activeKind`), Done (`doneKind`) — as part
    /// of the schema migration, idempotently.
    func columns() throws -> [BoardColumn]

    /// Every task, ordered by its column's `sortOrder` then its own —
    /// callers group by `columnID` to render the board (spec §6.3a). A
    /// single flat list rather than a pre-grouped shape: grouping is a
    /// one-line `Dictionary(grouping:by:)` for any caller that wants it, and
    /// this keeps the protocol from inventing a return type solely to mirror
    /// UI structure.
    func all() throws -> [TaskItem]

    /// Creates a new task in `columnID`, appended after that column's
    /// current last task (or first, if the column is empty), and persists
    /// it immediately.
    @discardableResult
    func create(title: String, columnID: BoardColumn.ID) throws -> TaskItem

    /// Persists every mutable field of an existing task — title, detail,
    /// priority, due date — and stamps `updatedAt`. The row must already
    /// exist; unknown ids throw. Does not move the task between columns;
    /// use `move(id:columnID:before:after:)` for that, since a move also
    /// needs a fresh `sortOrder` and may touch `completedAt`.
    func update(_ task: TaskItem) throws

    /// Deletes a task. A no-op if `id` does not exist.
    func delete(id: TaskItem.ID) throws

    /// Moves the task with `id` into `columnID`, at a fractional
    /// `sortOrder` strictly between `before` and `after`'s current
    /// positions (spec §5 "why sort_order REAL") — pass `nil` for either
    /// bound to move to that end of the column. Entering a `doneKind`
    /// column from one that wasn't stamps `completedAt`; leaving a
    /// `doneKind` column clears it (spec §6.3a). This rule lives here, not
    /// in the UI, so every caller — drag-and-drop and any future one — gets
    /// it for free.
    @discardableResult
    func move(id: TaskItem.ID, columnID: BoardColumn.ID, before: TaskItem.ID?, after: TaskItem.ID?) throws -> TaskItem

    /// Full-text search over title and detail via the `task_fts` index
    /// (`TaskSchema`), most relevant match first. Returns an empty array for
    /// a blank query.
    func search(_ query: String) throws -> [TaskItem]
}
