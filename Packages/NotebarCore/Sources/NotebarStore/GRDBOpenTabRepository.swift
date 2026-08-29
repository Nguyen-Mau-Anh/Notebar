import GRDB
import NotebarCore

/// The GRDB implementation of `OpenTabRepository`.
public final class GRDBOpenTabRepository: OpenTabRepository {
    private let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    public func all() throws -> [OpenTab] {
        try dbQueue.read { db in
            try OpenTabRow.order(Column("sort_order")).fetchAll(db).map(\.asOpenTab)
        }
    }

    public func replaceAll(_ tabs: [OpenTab]) throws {
        try dbQueue.write { db in
            try OpenTabRow.deleteAll(db)
            for tab in tabs {
                let row = OpenTabRow(tab)
                try row.insert(db)
            }
        }
    }
}
