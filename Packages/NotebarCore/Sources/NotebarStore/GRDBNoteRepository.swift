import Foundation
import GRDB
import NotebarCore

/// The GRDB implementation of `NoteRepository`. A Windows port swaps this
/// type out for something else; every call site elsewhere keeps compiling
/// unchanged because they only ever see `NoteRepository`.
public final class GRDBNoteRepository: NoteRepository {
    private let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    public func all() throws -> [Note] {
        try dbQueue.read { db in
            try NoteRow.order(Column("sort_order")).fetchAll(db).map(\.asNote)
        }
    }

    @discardableResult
    public func create() throws -> Note {
        try dbQueue.write { db in
            let maxSortOrder = try Double.fetchOne(db, sql: "SELECT MAX(sort_order) FROM note")
            let now = Date()
            let note = Note(sortOrder: (maxSortOrder ?? 0) + 1, isPinned: false)
                .assigningTimestamps(createdAt: now, updatedAt: now)
            let row = NoteRow(note)
            try row.insert(db)
            return row.asNote
        }
    }

    public func update(_ note: Note) throws {
        try dbQueue.write { db in
            var row = NoteRow(note)
            row.updatedAt = Date()
            // `body` and `body_plain` land in this one `UPDATE` statement —
            // deliverable 3's "same transaction" requirement is structural
            // here, not just documented, since `NoteRow.init` always derives
            // `bodyPlain` from `body` and there is no path that writes one
            // without the other. GRDB's `update(_:)` throws
            // `RecordError.recordNotFound` on its own when `note.id`
            // matches no row, so there is nothing extra to check here.
            try row.update(db)
        }
    }

    public func delete(id: Note.ID) throws {
        try dbQueue.write { db in
            _ = try NoteRow.deleteOne(db, key: id)
        }
    }

    @discardableResult
    public func reorder(id: Note.ID, before: Note.ID?, after: Note.ID?) throws -> Note {
        try dbQueue.write { db in
            guard var row = try NoteRow.fetchOne(db, key: id) else {
                throw NotebarStoreError.noteNotFound(id)
            }
            let beforeOrder = try before.flatMap {
                try Double.fetchOne(db, sql: "SELECT sort_order FROM note WHERE id = ?", arguments: [$0])
            }
            let afterOrder = try after.flatMap {
                try Double.fetchOne(db, sql: "SELECT sort_order FROM note WHERE id = ?", arguments: [$0])
            }
            row.sortOrder = Self.fractionalOrder(before: beforeOrder, after: afterOrder)
            row.updatedAt = Date()
            try row.update(db)
            return row.asNote
        }
    }

    public func search(_ query: String) throws -> [Note] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let pattern = FTS5Pattern(matchingAllTokensIn: trimmed) else {
            return []
        }
        return try dbQueue.read { db in
            try NoteRow.fetchAll(
                db,
                sql: """
                SELECT note.* FROM note
                JOIN note_fts ON note_fts.rowid = note.rowid
                WHERE note_fts MATCH ?
                ORDER BY rank
                """,
                arguments: [pattern]
            ).map(\.asNote)
        }
    }

    /// Fractional ordering (spec §5 "why sort_order REAL"): the midpoint of
    /// two neighbours, or one unit past whichever single neighbour exists,
    /// or `0` for an empty list. A compaction pass to renormalize as gaps
    /// approach float precision is future work, not needed at this note
    /// count.
    private static func fractionalOrder(before: Double?, after: Double?) -> Double {
        switch (before, after) {
        case let (b?, a?): return (b + a) / 2
        case let (b?, nil): return b + 1
        case let (nil, a?): return a - 1
        case (nil, nil): return 0
        }
    }
}

private extension Note {
    func assigningTimestamps(createdAt: Date, updatedAt: Date) -> Note {
        var copy = self
        copy.createdAt = createdAt
        copy.updatedAt = updatedAt
        return copy
    }
}
