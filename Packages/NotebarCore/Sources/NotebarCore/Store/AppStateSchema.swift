import Foundation

/// The SQL schema for `app_state`, as constants rather than only prose — see
/// `NoteSchema` for why. Matches spec §5's `app_state` table: a generic
/// key/value store so every future small preference (Activation, Data,
/// General — spec §6.5) reuses this same table instead of adding one of its
/// own.
public enum AppStateSchema {
    /// Migration name registered with GRDB's `DatabaseMigrator` in
    /// `NotebarStore`. A new migration alongside `NoteSchema.migrationName`,
    /// `OpenTabSchema.migrationName`, and `TaskSchema.migrationName` —
    /// existing databases pick this up on next launch without recreating the
    /// file, and without touching any migration already shipped.
    public static let migrationName = "createAppState"

    /// The row key `theme` is stored under.
    public static let themeKey = "theme"

    public static let createAppStateTable = """
    CREATE TABLE app_state (
      key   TEXT PRIMARY KEY,
      value TEXT NOT NULL
    )
    """
}
