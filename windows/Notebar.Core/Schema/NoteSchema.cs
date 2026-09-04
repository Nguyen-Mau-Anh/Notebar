namespace Notebar.Core.Schema;

/// <summary>The SQL schema for notes, as constants rather than only prose, so the
/// store never writes SQL the core does not already know about.</summary>
/// <remarks>
/// The macOS database reached this shape across four migrations — plain body,
/// then an RTF blob, then RTFD, then a plain shadow column — because each step
/// had to preserve data already on real machines. The Windows database is
/// independent and starts empty, so this is written once in its final form. That
/// is the whole practical benefit of not sharing a file between the platforms.
///
/// Everything from here on is additive only: never edit a migration that has
/// shipped, because a database that already ran it will not run it again and the
/// two will silently diverge.
/// </remarks>
public static class NoteSchema
{
    public const string MigrationName = "createNote";

    public const string CreateNoteTable = """
        CREATE TABLE note (
          id         TEXT PRIMARY KEY,
          title      TEXT NOT NULL DEFAULT '',
          body_html  TEXT NOT NULL DEFAULT '',
          body_plain TEXT NOT NULL DEFAULT '',
          is_pinned  INTEGER NOT NULL DEFAULT 0,
          sort_order REAL NOT NULL,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
        """;

    /// <summary>External-content FTS5 table over note. content_rowid='rowid' uses
    /// SQLite's implicit rowid alias — note is a normal table, so this works even
    /// though id is a TEXT UUID rather than the rowid.</summary>
    public const string CreateNoteFtsTable = """
        CREATE VIRTUAL TABLE note_fts USING fts5(
          title,
          body_plain,
          content='note',
          content_rowid='rowid'
        )
        """;

    /// <summary>Standard FTS5 external-content sync triggers. The repository always
    /// writes body_html and body_plain together in one row write, and these fire
    /// within that same write, so note_fts can never observe one column updated
    /// without the other.</summary>
    public const string NoteFtsTriggers = """
        CREATE TRIGGER note_ai AFTER INSERT ON note BEGIN
          INSERT INTO note_fts(rowid, title, body_plain) VALUES (new.rowid, new.title, new.body_plain);
        END;
        CREATE TRIGGER note_ad AFTER DELETE ON note BEGIN
          INSERT INTO note_fts(note_fts, rowid, title, body_plain) VALUES ('delete', old.rowid, old.title, old.body_plain);
        END;
        CREATE TRIGGER note_au AFTER UPDATE ON note BEGIN
          INSERT INTO note_fts(note_fts, rowid, title, body_plain) VALUES ('delete', old.rowid, old.title, old.body_plain);
          INSERT INTO note_fts(rowid, title, body_plain) VALUES (new.rowid, new.title, new.body_plain);
        END;
        """;
}

/// <summary>The open-tab strip. Deliberately generic (kind/ref_id) rather than a
/// note_id column, so task tabs slot in later without a schema change.</summary>
public static class OpenTabSchema
{
    public const string MigrationName = "createOpenTab";

    public const string CreateOpenTabTable = """
        CREATE TABLE open_tab (
          id         TEXT PRIMARY KEY,
          kind       TEXT NOT NULL,
          ref_id     TEXT NOT NULL,
          sort_order REAL NOT NULL,
          is_active  INTEGER NOT NULL DEFAULT 0
        )
        """;
}
