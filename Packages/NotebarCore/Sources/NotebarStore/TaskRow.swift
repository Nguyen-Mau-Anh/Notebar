import Foundation
import GRDB
import NotebarCore

/// The GRDB-mapped row for `TaskSchema.createTaskTable`. See `NoteRow` for
/// why this bridge type exists rather than `TaskItem` itself conforming to
/// GRDB's record protocols.
struct TaskRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "task"

    var id: String
    var title: String
    var detailPlain: String
    var columnID: String
    var sortOrder: Double
    var priority: Int
    var dueAt: Date?
    var completedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title, priority
        case detailPlain = "detail_plain"
        case columnID = "column_id"
        case sortOrder = "sort_order"
        case dueAt = "due_at"
        case completedAt = "completed_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

extension TaskRow {
    init(_ task: TaskItem) {
        id = task.id
        title = task.title
        detailPlain = task.detailPlain
        columnID = task.columnID
        sortOrder = task.sortOrder
        priority = task.priority
        dueAt = task.dueAt
        completedAt = task.completedAt
        createdAt = task.createdAt
        updatedAt = task.updatedAt
    }

    var asTaskItem: TaskItem {
        TaskItem(
            id: id,
            title: title,
            detailPlain: detailPlain,
            columnID: columnID,
            sortOrder: sortOrder,
            priority: priority,
            dueAt: dueAt,
            completedAt: completedAt,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
