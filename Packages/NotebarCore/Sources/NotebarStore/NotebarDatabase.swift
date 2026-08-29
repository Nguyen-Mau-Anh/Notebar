import Foundation
import GRDB
import NotebarCore

/// Opens the GRDB-backed store and hands back ready-to-use repositories.
/// This is the only file in the app target's dependency graph that needs to
/// know `DatabaseQueue` exists — everything else, including `PanelViewModel`,
/// talks to `NoteRepository`/`OpenTabRepository` (spec §3, rule 1's whole
/// point: GRDB stays fully behind those protocols).
public enum NotebarDatabase {
    public struct Repositories {
        public let notes: NoteRepository
        public let openTabs: OpenTabRepository
        public let tasks: TaskRepository
        public let appState: AppStateRepository
    }

    /// Opens (creating if needed) the on-disk database in this app's
    /// Application Support directory and runs any pending migrations.
    public static func openDefault() throws -> Repositories {
        try makeRepositories(dbQueue: DatabaseQueue(path: defaultDatabaseURL().path))
    }

    /// An in-memory database, migrated the same way. Used by tests and as a
    /// fallback if the on-disk store can't be opened.
    public static func openInMemory() throws -> Repositories {
        try makeRepositories(dbQueue: DatabaseQueue())
    }

    private static func makeRepositories(dbQueue: DatabaseQueue) throws -> Repositories {
        try Migrations.migrator.migrate(dbQueue)
        return Repositories(
            notes: GRDBNoteRepository(dbQueue: dbQueue),
            openTabs: GRDBOpenTabRepository(dbQueue: dbQueue),
            tasks: GRDBTaskRepository(dbQueue: dbQueue),
            appState: GRDBAppStateRepository(dbQueue: dbQueue)
        )
    }

    static func defaultDatabaseURL() throws -> URL {
        let fileManager = FileManager.default
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = appSupport.appendingPathComponent("Notebar", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("notebar.sqlite")
    }
}
