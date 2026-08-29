import GRDB
import NotebarCore

/// The GRDB-mapped row for `TaskSchema.createBoardColumnTable`. See
/// `NoteRow` for why this bridge type exists rather than `BoardColumn`
/// itself conforming to GRDB's record protocols.
struct BoardColumnRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "board_column"

    var id: String
    var boardID: String
    var name: String
    var kind: String
    var sortOrder: Double
    var wipLimit: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, kind
        case boardID = "board_id"
        case sortOrder = "sort_order"
        case wipLimit = "wip_limit"
    }
}

extension BoardColumnRow {
    init(_ column: BoardColumn) {
        id = column.id
        boardID = column.boardID
        name = column.name
        kind = column.kind
        sortOrder = column.sortOrder
        wipLimit = column.wipLimit
    }

    var asBoardColumn: BoardColumn {
        BoardColumn(id: id, boardID: boardID, name: name, kind: kind, sortOrder: sortOrder, wipLimit: wipLimit)
    }
}
