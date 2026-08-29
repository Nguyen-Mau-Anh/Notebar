import NotebarCore

/// Errors specific to the GRDB-backed implementations. Kept separate from
/// `NotebarCore`'s protocols, which stay silent on error types — a Windows
/// implementation is free to throw its own.
public enum NotebarStoreError: Error, Equatable {
    /// `update(_:)` or `reorder(id:before:after:)` was called with an id
    /// that has no matching row.
    case noteNotFound(Note.ID)

    /// `move(id:columnID:before:after:)` was called with a task id that has
    /// no matching row.
    case taskNotFound(TaskItem.ID)

    /// `create(title:columnID:)` or `move(id:columnID:before:after:)` was
    /// called with a column id that has no matching row.
    case boardColumnNotFound(BoardColumn.ID)
}
