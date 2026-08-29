import Foundation
import GRDB
import NotebarCore

/// The GRDB-mapped row for `NoteSchema.createNoteTable`. `Note` itself
/// (`NotebarCore`) can't conform to GRDB's record protocols directly —
/// that would require importing GRDB from a module that must stay
/// dependency-free — so this type exists purely to bridge the two.
struct NoteRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "note"

    var id: String
    var title: String
    var body: String
    var bodyPlain: String
    var isPinned: Bool
    var sortOrder: Double
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title, body
        case bodyPlain = "body_plain"
        case isPinned = "is_pinned"
        case sortOrder = "sort_order"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

extension NoteRow {
    /// `bodyPlain` is always set from `body` right here, in the same
    /// initializer every write path uses, rather than left for callers to
    /// remember — this is what makes deliverable 3's "same transaction, so
    /// the index can't drift" guarantee hold structurally instead of by
    /// convention. Once rich text lands, this becomes the one place that
    /// changes: deriving plain text from an RTF blob instead of copying it.
    init(_ note: Note) {
        id = note.id
        title = note.derivedTitle
        body = note.body
        bodyPlain = note.body
        isPinned = note.isPinned
        sortOrder = note.sortOrder
        createdAt = note.createdAt
        updatedAt = note.updatedAt
    }

    var asNote: Note {
        Note(
            id: id,
            title: title,
            body: body,
            createdAt: createdAt,
            updatedAt: updatedAt,
            sortOrder: sortOrder,
            isPinned: isPinned
        )
    }
}
