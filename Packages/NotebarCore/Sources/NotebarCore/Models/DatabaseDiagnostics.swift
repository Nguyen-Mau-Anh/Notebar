import Foundation

/// A snapshot of facts about the on-disk store, for Settings → Data and
/// Export Diagnostics (spec §6.4b). Every field here is a fact *about* the
/// database — a path, a byte count, a list of migration names — never a row
/// of user content, so this type is structurally incapable of carrying a
/// note's title or body even by accident.
public struct DatabaseDiagnostics: Equatable, Sendable {
    /// Where the database file lives on disk, or `nil` when the app is
    /// running on the in-memory fallback (`AppDelegate`'s degrade path when
    /// the on-disk store couldn't be opened).
    public var path: String?

    /// The database file's size on disk in bytes (including any `-wal`/
    /// `-shm` sidecar files), or `nil` if it couldn't be read — a missing
    /// file, a permissions problem, or the in-memory fallback.
    public var sizeOnDisk: Int?

    /// The name of every migration `DatabaseMigrator` has recorded as
    /// applied to this database, in registration order (see
    /// `Migrations.swift`). Names only — e.g. `"NoteBodyRTFDSchema"` — never
    /// the rows a migration touched.
    public var appliedMigrations: [String]

    public init(path: String?, sizeOnDisk: Int?, appliedMigrations: [String]) {
        self.path = path
        self.sizeOnDisk = sizeOnDisk
        self.appliedMigrations = appliedMigrations
    }
}
