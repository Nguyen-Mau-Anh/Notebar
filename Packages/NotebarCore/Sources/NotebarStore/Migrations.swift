import GRDB
import NotebarCore

/// The single place migrations are registered, so opening a fresh database
/// and opening an upgraded one go through the same path. Each migration is
/// named after the constant `NotebarCore`'s schema declares
/// (`NoteSchema.migrationName`, etc.) so the two stay obviously paired.
enum Migrations {
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration(NoteSchema.migrationName) { db in
            try db.execute(sql: NoteSchema.createNoteTable)
            try db.execute(sql: NoteSchema.createNoteFTSTable)
            try db.execute(sql: NoteSchema.noteFTSTriggers)
        }

        migrator.registerMigration(OpenTabSchema.migrationName) { db in
            try db.execute(sql: OpenTabSchema.createOpenTabTable)
        }

        return migrator
    }
}
