import Foundation
import GRDB
import NotebarCore

/// The GRDB implementation of `TaskRepository`. A Windows port swaps this
/// type out for something else; every call site elsewhere keeps compiling
/// unchanged because they only ever see `TaskRepository`.
public final class GRDBTaskRepository: TaskRepository {
    private let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    public func columns() throws -> [BoardColumn] {
        try dbQueue.read { db in
            try BoardColumnRow.order(Column("sort_order")).fetchAll(db).map(\.asBoardColumn)
        }
    }

    public func all() throws -> [TaskItem] {
        try dbQueue.read { db in
            try TaskRow.fetchAll(
                db,
                sql: """
                SELECT task.* FROM task
                JOIN board_column ON board_column.id = task.column_id
                ORDER BY board_column.sort_order, task.sort_order
                """
            ).map(\.asTaskItem)
        }
    }

    @discardableResult
    public func create(title: String, columnID: BoardColumn.ID) throws -> TaskItem {
        try dbQueue.write { db in
            guard try BoardColumnRow.fetchOne(db, key: columnID) != nil else {
                throw NotebarStoreError.boardColumnNotFound(columnID)
            }
            let maxSortOrder = try Double.fetchOne(
                db, sql: "SELECT MAX(sort_order) FROM task WHERE column_id = ?", arguments: [columnID]
            )
            let now = Date()
            let task = TaskItem(title: title, columnID: columnID, sortOrder: (maxSortOrder ?? 0) + 1, createdAt: now, updatedAt: now)
            let row = TaskRow(task)
            try row.insert(db)
            return row.asTaskItem
        }
    }

    public func update(_ task: TaskItem) throws {
        try dbQueue.write { db in
            var row = TaskRow(task)
            row.updatedAt = Date()
            // `title` and `detail_plain` land in this one `UPDATE`
            // statement — same "same transaction" guarantee `GRDBNoteRepository`
            // documents, and for the same structural reason: there is no
            // path that writes one without the other. GRDB's `update(_:)`
            // throws `RecordError.recordNotFound` on its own when
            // `task.id` matches no row.
            try row.update(db)
        }
    }

    public func delete(id: TaskItem.ID) throws {
        try dbQueue.write { db in
            _ = try TaskRow.deleteOne(db, key: id)
        }
    }

    @discardableResult
    public func move(id: TaskItem.ID, columnID: BoardColumn.ID, before: TaskItem.ID?, after: TaskItem.ID?) throws -> TaskItem {
        try dbQueue.write { db in
            guard var row = try TaskRow.fetchOne(db, key: id) else {
                throw NotebarStoreError.taskNotFound(id)
            }
            guard let destination = try BoardColumnRow.fetchOne(db, key: columnID) else {
                throw NotebarStoreError.boardColumnNotFound(columnID)
            }
            let previousColumn = try BoardColumnRow.fetchOne(db, key: row.columnID)
            let wasInDoneColumn = previousColumn?.kind == BoardColumn.doneKind
            let entersDoneColumn = destination.kind == BoardColumn.doneKind

            let beforeOrder = try before.flatMap {
                try Double.fetchOne(db, sql: "SELECT sort_order FROM task WHERE id = ?", arguments: [$0])
            }
            let afterOrder = try after.flatMap {
                try Double.fetchOne(db, sql: "SELECT sort_order FROM task WHERE id = ?", arguments: [$0])
            }

            row.columnID = columnID
            row.sortOrder = Self.fractionalOrder(before: beforeOrder, after: afterOrder)
            row.updatedAt = Date()

            // The `completed_at` rule lives here, not in the UI, so every
            // caller — drag-and-drop today, anything else later — gets it
            // for free (spec §6.3a). Entering a done-kind column from one
            // that wasn't stamps it; leaving a done-kind column clears it.
            // Reordering within Done (both `wasInDoneColumn` and
            // `entersDoneColumn` true) leaves the existing timestamp alone,
            // rather than re-stamping it on every drag.
            if entersDoneColumn && !wasInDoneColumn {
                row.completedAt = row.updatedAt
            } else if !entersDoneColumn {
                row.completedAt = nil
            }

            try row.update(db)
            return row.asTaskItem
        }
    }

    public func search(_ query: String) throws -> [TaskItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let pattern = FTS5Pattern(matchingAllTokensIn: trimmed) else {
            return []
        }
        return try dbQueue.read { db in
            try TaskRow.fetchAll(
                db,
                sql: """
                SELECT task.* FROM task
                JOIN task_fts ON task_fts.rowid = task.rowid
                WHERE task_fts MATCH ?
                ORDER BY rank
                """,
                arguments: [pattern]
            ).map(\.asTaskItem)
        }
    }

    /// Fractional ordering (spec §5 "why sort_order REAL") — identical
    /// reasoning and behaviour to `GRDBNoteRepository.fractionalOrder`,
    /// duplicated rather than shared because the two repositories otherwise
    /// share no code and a shared helper would be a coupling with no other
    /// purpose.
    private static func fractionalOrder(before: Double?, after: Double?) -> Double {
        switch (before, after) {
        case let (b?, a?): return (b + a) / 2
        case let (b?, nil): return b + 1
        case let (nil, a?): return a - 1
        case (nil, nil): return 0
        }
    }
}
