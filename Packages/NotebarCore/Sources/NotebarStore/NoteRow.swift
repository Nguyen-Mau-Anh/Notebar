import Foundation
import GRDB
import NotebarCore

/// The GRDB-mapped row for `NoteSchema.createNoteTable` as brought up to date
/// by `NoteBodyRTFSchema` (`body_rtf` in, `body` out). `Note` itself
/// (`NotebarCore`) can't conform to GRDB's record protocols directly —
/// that would require importing GRDB from a module that must stay
/// dependency-free — so this type exists purely to bridge the two.
struct NoteRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "note"

    var id: String
    var title: String
    var bodyRTF: Data
    var bodyPlain: String
    var isPinned: Bool
    var sortOrder: Double
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title
        case bodyRTF = "body_rtf"
        case bodyPlain = "body_plain"
        case isPinned = "is_pinned"
        case sortOrder = "sort_order"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

extension NoteRow {
    /// Copies `bodyRTF` and `bodyPlain` straight from `Note` rather than
    /// re-deriving one from the other, unlike the plain-text version this
    /// replaced. `Note` itself can't derive `bodyPlain` from `bodyRTF` — that
    /// needs AppKit, which `NotebarCore` must never import — so whoever last
    /// held the live `NSAttributedString` (`NoteEditorView`'s coordinator, or
    /// the RTF-migration backfill) already computed both together, via
    /// `NoteRTF`, before a `Note` value ever reaches here. This initializer's
    /// job is only to carry both into one row write, which is what keeps
    /// deliverable 3's "same transaction, so the index can't drift" guarantee
    /// true structurally: there is no path from a `Note` to a persisted row
    /// that writes one without the other.
    init(_ note: Note) {
        id = note.id
        title = note.title
        bodyRTF = note.bodyRTF
        bodyPlain = note.bodyPlain
        isPinned = note.isPinned
        sortOrder = note.sortOrder
        createdAt = note.createdAt
        updatedAt = note.updatedAt
    }

    var asNote: Note {
        Note(
            id: id,
            title: title,
            bodyRTF: bodyRTF,
            bodyPlain: bodyPlain,
            createdAt: createdAt,
            updatedAt: updatedAt,
            sortOrder: sortOrder,
            isPinned: isPinned
        )
    }
}

/// The row shape `GRDBNoteRepository.summaries()` actually selects: `id`,
/// `title`, and `updated_at` only, never `body_rtf` (spec §6.2c deliverable
/// 4). A separate type from `NoteRow` rather than decoding a partial
/// `NoteRow` — `NoteRow`'s `Codable` conformance is derived from all six of
/// its stored properties, so decoding it from a three-column row would fail
/// outright rather than silently leaving `bodyRTF` empty.
struct NoteSummaryRow: Codable, FetchableRecord {
    var id: String
    var title: String
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title
        case updatedAt = "updated_at"
    }
}
