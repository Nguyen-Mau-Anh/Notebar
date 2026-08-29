import GRDB
import NotebarCore

/// The GRDB-mapped row for `OpenTabSchema.createOpenTabTable`. See
/// `NoteRow` for why this bridge type exists rather than `OpenTab` itself
/// conforming to GRDB's record protocols.
struct OpenTabRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "open_tab"

    var id: String
    var kind: String
    var refID: String
    var sortOrder: Double
    var isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id, kind
        case refID = "ref_id"
        case sortOrder = "sort_order"
        case isActive = "is_active"
    }
}

extension OpenTabRow {
    init(_ tab: OpenTab) {
        id = tab.id
        kind = tab.kind
        refID = tab.refID
        sortOrder = tab.sortOrder
        isActive = tab.isActive
    }

    var asOpenTab: OpenTab {
        OpenTab(id: id, kind: kind, refID: refID, sortOrder: sortOrder, isActive: isActive)
    }
}
