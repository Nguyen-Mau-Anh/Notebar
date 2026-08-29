import AppKit
import GRDB
import NotebarCore

/// The single place migrations are registered, so opening a fresh database
/// and opening an upgraded one go through the same path. Each migration is
/// named after the constant `NotebarCore`'s schema declares
/// (`NoteSchema.migrationName`, etc.) so the two stay obviously paired.
///
/// Every migration here, once shipped, is permanent: the user has real notes
/// and tasks in this database, and `DatabaseMigrator` identifies a migration
/// by its registered name and never re-runs one it already applied. Changing
/// an existing migration's body does nothing for a database that already ran
/// it — the fix for an already-shipped mistake is always a new migration, not
/// an edit to an old one. `NoteBodyRTFSchema.migrationName` below is exactly
/// that: a follow-up to `NoteSchema.migrationName`, not a change to it.
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

        migrator.registerMigration(TaskSchema.migrationName) { db in
            try db.execute(sql: TaskSchema.createBoardTable)
            try db.execute(sql: TaskSchema.createBoardColumnTable)
            try db.execute(sql: TaskSchema.createTaskTable)
            try db.execute(sql: TaskSchema.createTaskFTSTable)
            try db.execute(sql: TaskSchema.taskFTSTriggers)
            try db.execute(sql: TaskSchema.seedDefaultBoardAndColumns)
        }

        migrator.registerMigration(AppStateSchema.migrationName) { db in
            try db.execute(sql: AppStateSchema.createAppStateTable)
        }

        // Registered last, deliberately: `DatabaseMigrator` applies pending
        // migrations in registration order and rejects a new migration
        // inserted before ones a database has already applied. A user
        // upgrading already has `OpenTabSchema`/`TaskSchema`/`AppStateSchema`
        // applied, so this — spec §6.2's rich-text editor — must be
        // registered after all of them, not next to `NoteSchema` where it
        // reads most naturally. Adds `body_rtf` and converts every existing
        // note's plain-text body into it, so nothing the user already wrote
        // is lost or shows up blank once the editor switches to reading
        // `body_rtf` instead of the plain `body` column this drops.
        // `body_plain` — already exactly that plain text, per `NoteSchema`'s
        // trigger setup — is left as-is throughout.
        migrator.registerMigration(NoteBodyRTFSchema.migrationName) { db in
            try db.execute(sql: NoteBodyRTFSchema.addBodyRTFColumn)

            let rows = try Row.fetchAll(db, sql: "SELECT rowid, body_plain FROM note")
            for row in rows {
                let rowid: Int64 = row["rowid"]
                let plainBody: String = row["body_plain"]
                let rtfData = NoteRTF.data(from: NSAttributedString(string: plainBody))
                try db.execute(
                    sql: "UPDATE note SET body_rtf = ? WHERE rowid = ?",
                    arguments: [rtfData, rowid]
                )
            }

            try db.execute(sql: NoteBodyRTFSchema.dropBodyColumn)
        }

        return migrator
    }
}
