import Foundation

/// The SQL schema for `link` (spec §5's `link` table), as constants rather
/// than only prose — see `NoteSchema` for why.
///
/// **This table has been specced since day one and was never built.** Spec
/// §6.4: "Six migrations shipped without it while notes and tasks were built
/// separately, which is exactly the retrofit §5 warned about." The shape
/// below is copied from §5 unchanged — the generic edge table still holds
/// for note→task, task→note, note→note, and task→task, with backlinks as
/// the reverse query on `idx_link_dst` — so this migration is the cost of
/// building it, not of redesigning it.
public enum LinkSchema {
    /// Migration name registered with GRDB's `DatabaseMigrator` in
    /// `NotebarStore`, added after every migration already shipped — see
    /// `Migrations.swift`'s module doc comment on why a new migration, never
    /// an edit to one already applied, is the only way to change schema a
    /// real database may have already run.
    public static let migrationName = "createLink"

    public static let createLinkTable = """
    CREATE TABLE link (
      id         TEXT PRIMARY KEY,
      src_type   TEXT NOT NULL,
      src_id     TEXT NOT NULL,
      dst_type   TEXT NOT NULL,
      dst_id     TEXT NOT NULL,
      kind       TEXT NOT NULL DEFAULT 'references',
      created_at TEXT NOT NULL,
      UNIQUE (src_type, src_id, dst_type, dst_id, kind)
    )
    """

    public static let createSrcIndex = "CREATE INDEX idx_link_src ON link(src_type, src_id)"

    /// What makes backlinks a cheap reverse query (spec §5) — created now,
    /// alongside the table, even though nothing reads it until the backlinks
    /// task lands. Adding an index to a table that already holds rows is the
    /// expensive retrofit; adding it in the same migration that creates the
    /// table costs nothing extra.
    public static let createDstIndex = "CREATE INDEX idx_link_dst ON link(dst_type, dst_id)"

    /// Cascade cleanup: deleting a note or task removes every link that
    /// touches it, on either end. This is the "decide which" call spec §6.4
    /// leaves open for this task (tombstones — rendering a chip whose target
    /// is gone — are the *next* task, not this one): a dangling `link` row
    /// pointing at an id that can never resolve again is indistinguishable
    /// from a bug, and nothing about tombstones needs the row to survive —
    /// a tombstone only needs `fetch(id:)` to come back `nil`, which it
    /// already does the instant the note or task itself is deleted. Cascading
    /// also means the next task's backlinks query never has to filter out
    /// references to entities that no longer exist.
    ///
    /// Two triggers, not one, because SQLite triggers fire on a single table
    /// and `link` has no real foreign key to either `note` or `task` — the
    /// same row's `dst_id` might belong to either table depending on
    /// `dst_type`, so a normal `ON DELETE CASCADE` foreign key (as
    /// `board_column` uses against `board`) can't express this.
    public static let cascadeOnNoteDelete = """
    CREATE TRIGGER link_cleanup_note_delete AFTER DELETE ON note BEGIN
      DELETE FROM link WHERE (src_type = 'note' AND src_id = old.id) OR (dst_type = 'note' AND dst_id = old.id);
    END;
    """

    public static let cascadeOnTaskDelete = """
    CREATE TRIGGER link_cleanup_task_delete AFTER DELETE ON task BEGIN
      DELETE FROM link WHERE (src_type = 'task' AND src_id = old.id) OR (dst_type = 'task' AND dst_id = old.id);
    END;
    """
}
