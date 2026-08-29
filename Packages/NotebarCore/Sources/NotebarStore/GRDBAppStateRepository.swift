import GRDB
import NotebarCore

/// The GRDB implementation of `AppStateRepository`.
public final class GRDBAppStateRepository: AppStateRepository {
    private let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    public func theme() throws -> Theme {
        let stored = try dbQueue.read { db in
            try AppStateRow.fetchOne(db, key: AppStateSchema.themeKey)
        }
        // A missing key (never saved) and an unrecognised value (someone
        // hand-edited the database, or a future build removes a case) both
        // fall back to the default rather than throwing — spec §6.5's
        // control must never be the reason the app won't launch.
        guard let stored, let theme = Theme(rawValue: stored.value) else {
            return .default
        }
        return theme
    }

    public func setTheme(_ theme: Theme) throws {
        try dbQueue.write { db in
            try AppStateRow(key: AppStateSchema.themeKey, value: theme.rawValue).save(db)
        }
    }
}
