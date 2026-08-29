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
        public let links: LinkRepository
        public let appState: AppStateRepository
        public let diagnostics: DiagnosticsRepository
    }

    /// Opens (creating if needed) the on-disk database in this app's
    /// Application Support directory and runs any pending migrations.
    public static func openDefault() throws -> Repositories {
        let url = try defaultDatabaseURL()
        return try makeRepositories(dbQueue: DatabaseQueue(path: url.path), databasePath: url)
    }

    /// An in-memory database, migrated the same way. Used by tests and as a
    /// fallback if the on-disk store can't be opened. `databasePath` is nil
    /// here — there is no on-disk file for `DiagnosticsRepository` to report
    /// a size for, and Settings → Data shows that honestly rather than
    /// inventing a path nothing backs.
    public static func openInMemory() throws -> Repositories {
        try makeRepositories(dbQueue: DatabaseQueue(), databasePath: nil)
    }

    private static func makeRepositories(dbQueue: DatabaseQueue, databasePath: URL?) throws -> Repositories {
        // Diffed before/after rather than just logging "migrated" — a
        // second launch against an already-current database should say so
        // was a no-op, not repeat the same "ran N migrations" line every
        // time the app opens (spec §6.4b: "migration runs" worth a log
        // entry, not log noise).
        let alreadyApplied = try dbQueue.read { db in try Migrations.migrator.appliedIdentifiers(db) }
        do {
            try Migrations.migrator.migrate(dbQueue)
        } catch {
            NotebarLog.store.error("database migration failed: \(String(describing: error), privacy: .public)")
            throw error
        }
        let nowApplied = try dbQueue.read { db in try Migrations.migrator.appliedMigrations(db) }
        let newlyApplied = nowApplied.filter { !alreadyApplied.contains($0) }
        if newlyApplied.isEmpty {
            NotebarLog.store.debug("database opened, no pending migrations")
        } else {
            NotebarLog.store.info("ran \(newlyApplied.count, privacy: .public) migration(s): \(newlyApplied.joined(separator: ", "), privacy: .public)")
        }
        return Repositories(
            notes: GRDBNoteRepository(dbQueue: dbQueue),
            openTabs: GRDBOpenTabRepository(dbQueue: dbQueue),
            tasks: GRDBTaskRepository(dbQueue: dbQueue),
            links: GRDBLinkRepository(dbQueue: dbQueue),
            appState: GRDBAppStateRepository(dbQueue: dbQueue),
            diagnostics: GRDBDiagnosticsRepository(dbQueue: dbQueue, path: databasePath)
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
