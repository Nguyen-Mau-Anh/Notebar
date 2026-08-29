import Foundation
import GRDB
import NotebarCore

/// The GRDB-mapped row for `LinkSchema.createLinkTable`. See `NoteRow` for
/// why this bridge type exists rather than `Link` itself conforming to
/// GRDB's record protocols. `srcType`/`dstType` are stored as their raw
/// `String` (`LinkEntityType.rawValue`) — GRDB persists exactly the two
/// columns `link` declares, and only `asLink` ever turns them back into the
/// enum `LinkRepository` deals in.
struct LinkRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "link"

    var id: String
    var srcType: String
    var srcId: String
    var dstType: String
    var dstId: String
    var kind: String
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, kind
        case srcType = "src_type"
        case srcId = "src_id"
        case dstType = "dst_type"
        case dstId = "dst_id"
        case createdAt = "created_at"
    }
}

extension LinkRow {
    init(_ link: Link) {
        id = link.id
        srcType = link.srcType.rawValue
        srcId = link.srcId
        dstType = link.dstType.rawValue
        dstId = link.dstId
        kind = link.kind
        createdAt = link.createdAt
    }

    /// Force-unwraps `srcType`/`dstType` back into `LinkEntityType`: every
    /// row in this table was written by `LinkRow.init(_:)` above, from a
    /// `LinkEntityType`'s own `rawValue`, so a row that fails to decode back
    /// would mean the database itself was hand-edited outside this app —
    /// not a case any caller can recover from, matching how `NoteRow.asNote`
    /// and `BoardColumnRow.asBoardColumn` also trust every column they read.
    var asLink: Link {
        Link(
            id: id,
            srcType: LinkEntityType(rawValue: srcType)!,
            srcId: srcId,
            dstType: LinkEntityType(rawValue: dstType)!,
            dstId: dstId,
            kind: kind,
            createdAt: createdAt
        )
    }
}
