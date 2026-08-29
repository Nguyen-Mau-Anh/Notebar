import Foundation

/// A single task card (spec §5's `task` table). Persisted through
/// `TaskRepository`; `NotebarStore` supplies the GRDB-backed implementation
/// so this module never has to import GRDB — see the architecture note on
/// `NoteRepository`, which this mirrors.
///
/// `detailPlain` is the only detail column for this milestone. Spec §5
/// ultimately wants a `detail_rtf` blob once rich text lands, the same way
/// `Note.body` is headed there — until then `detailPlain` *is* the detail,
/// and adding the blob column later is additive rather than a rework of
/// this type or of `task_fts` (`TaskSchema`).
public struct TaskItem: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var detailPlain: String
    public var columnID: String
    public var sortOrder: Double
    public var priority: Int
    public var dueAt: Date?
    public var completedAt: Date?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        title: String,
        detailPlain: String = "",
        columnID: String,
        sortOrder: Double = 0,
        priority: Int = 0,
        dueAt: Date? = nil,
        completedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.detailPlain = detailPlain
        self.columnID = columnID
        self.sortOrder = sortOrder
        self.priority = priority
        self.dueAt = dueAt
        self.completedAt = completedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
