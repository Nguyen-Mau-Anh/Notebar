import Foundation

/// The SQL schema for notes, as constants rather than only prose, so
/// `NotebarStore` never has to write SQL that this module doesn't already
/// know about (spec §5's stated source of truth for the schema).
///
/// `createNoteTable` below is the table's *original* shape — plain-text
/// `body` rather than an RTF blob — and stays exactly as it was written,
/// because this is a migration already run against real databases (see the
/// module doc comment on `Migrations`). `NoteBodyRTFSchema` further down is
/// the follow-up migration that adds `body_rtf` and drops `body`, bringing
/// the table to spec §5's current shape without editing this one.
///
/// Tasks, links, and tags (the rest of spec §5) are out of scope for this
/// milestone and are not declared here.
public enum NoteSchema {
    /// Migration name registered with GRDB's `DatabaseMigrator` in
    /// `NotebarStore`.
    public static let migrationName = "createNote"

    public static let createNoteTable = """
    CREATE TABLE note (
      id         TEXT PRIMARY KEY,
      title      TEXT NOT NULL DEFAULT '',
      body       TEXT NOT NULL DEFAULT '',
      body_plain TEXT NOT NULL DEFAULT '',
      is_pinned  INTEGER NOT NULL DEFAULT 0,
      sort_order REAL NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    """

    /// External-content FTS5 table over `note`, matching spec §5 exactly.
    /// `content_rowid='rowid'` uses SQLite's implicit rowid alias — `note`
    /// is a normal (non-`WITHOUT ROWID`) table, so this works even though
    /// `id` (the declared primary key) is a TEXT UUID, not the rowid.
    public static let createNoteFTSTable = """
    CREATE VIRTUAL TABLE note_fts USING fts5(
      title,
      body_plain,
      content='note',
      content_rowid='rowid'
    )
    """

    /// Standard FTS5 external-content sync triggers. `GRDBNoteRepository`
    /// always writes `body` and `body_plain` together in the same row write
    /// (deliverable 3's "same transaction" requirement), and these triggers
    /// fire within that same write, so `note_fts` can never observe one
    /// column updated without the other.
    public static let noteFTSTriggers = """
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
    """
}

/// The SQL schema for the open-tab strip (spec §5's `open_tab` table).
/// Deliberately generic (`kind`/`ref_id`) rather than a `note_id` column, so
/// task tabs slot in later without a schema change.
public enum OpenTabSchema {
    public static let migrationName = "createOpenTab"

    public static let createOpenTabTable = """
    CREATE TABLE open_tab (
      id         TEXT PRIMARY KEY,
      kind       TEXT NOT NULL,
      ref_id     TEXT NOT NULL,
      sort_order REAL NOT NULL,
      is_active  INTEGER NOT NULL DEFAULT 0
    )
    """
}

/// The rich-text follow-up to `NoteSchema` (spec §6.2/§6.2b): adds the
/// `body_rtf` blob the note editor's `NSTextView` now round-trips, and drops
/// the plain-text `body` column it replaces. A *new* migration rather than an
/// edit to `NoteSchema.createNoteTable` — the user's existing database
/// already ran that migration, and `DatabaseMigrator` never re-runs a
/// migration it has already applied, so changing that SQL would do nothing
/// for anyone upgrading and would only matter for a database created fresh
/// after this change, silently diverging the two.
///
/// `body_plain` is untouched: it already holds exactly the plain text every
/// existing note's `body` was (`NoteRow`'s old derivation copied one straight
/// into the other), so it needs no migrating and `note_fts` keeps working
/// through the whole migration without a rebuild.
public enum NoteBodyRTFSchema {
    public static let migrationName = "addNoteBodyRTF"

    /// Nullable, matching spec §5's `body_rtf BLOB` exactly: `Migrations`
    /// backfills every existing row within this same migration, so in
    /// practice no row is ever left NULL, but the column itself carries no
    /// `NOT NULL` constraint forcing that.
    public static let addBodyRTFColumn = "ALTER TABLE note ADD COLUMN body_rtf BLOB"

    /// Run only after the backfill above has given every row a `body_rtf`
    /// value — dropping `body` first would discard the plain text the
    /// backfill still needs to read.
    public static let dropBodyColumn = "ALTER TABLE note DROP COLUMN body"
}
