import Foundation
import GRDB
import NotebarCore

/// The GRDB implementation of `LinkRepository`. A Windows port swaps this
/// type out for something else; every call site elsewhere keeps compiling
/// unchanged because they only ever see `LinkRepository`.
public final class GRDBLinkRepository: LinkRepository {
    private let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    @discardableResult
    public func create(_ link: Link) throws -> Link {
        try dbQueue.write { db in
            let row = LinkRow(link)
            try row.insert(db)
            return row.asLink
        }
    }

    @discardableResult
    public func create(_ link: Link, savingNoteBody noteID: String, bodyRTF: Data, bodyPlain: String) throws -> Link {
        try dbQueue.write { db in
            guard var noteRow = try NoteRow.fetchOne(db, key: noteID) else {
                throw NotebarStoreError.noteNotFound(noteID)
            }
            // Both writes land in one `dbQueue.write` block, i.e. one SQLite
            // transaction: `insert(db)` below either lands with this
            // `update(db)` or neither does, satisfying deliverable 3's "a
            // chip can never exist without its row" in the same structural
            // way `GRDBNoteRepository.update` already guarantees `body_rtf`
            // and `body_plain` can't drift — one write, not two.
            noteRow.bodyRTF = bodyRTF
            noteRow.bodyPlain = bodyPlain
            noteRow.updatedAt = Date()
            try noteRow.update(db)

            let linkRow = LinkRow(link)
            try linkRow.insert(db)
            return linkRow.asLink
        }
    }

    public func delete(id: Link.ID) throws {
        try dbQueue.write { db in
            _ = try LinkRow.deleteOne(db, key: id)
        }
    }

    public func outgoing(from target: LinkTarget) throws -> [Link] {
        try dbQueue.read { db in
            try LinkRow
                .filter(Column("src_type") == target.type.rawValue && Column("src_id") == target.id)
                .fetchAll(db)
                .map(\.asLink)
        }
    }

    public func incoming(to target: LinkTarget) throws -> [Link] {
        try dbQueue.read { db in
            try LinkRow
                .filter(Column("dst_type") == target.type.rawValue && Column("dst_id") == target.id)
                .fetchAll(db)
                .map(\.asLink)
        }
    }
}
