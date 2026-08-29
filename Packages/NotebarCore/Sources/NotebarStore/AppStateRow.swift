import GRDB

/// The GRDB-mapped row for `AppStateSchema.createAppStateTable`. See
/// `NoteRow` for why this bridge type exists rather than mapping straight
/// onto a domain model — `app_state` is a plain key/value table with no
/// domain model of its own.
struct AppStateRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "app_state"

    var key: String
    var value: String
}
