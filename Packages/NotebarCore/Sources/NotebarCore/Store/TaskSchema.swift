import Foundation

/// The SQL schema for the tasks board, as constants rather than only prose —
/// see `NoteSchema` for why. Matches spec §5's `board`, `board_column`, and
/// `task` tables, with the same deliberate deviation `NoteSchema` documents
/// for `note`: `task` carries `detail_plain` only for this milestone, not
/// yet the `detail_rtf` blob spec §5 shows — see `TaskItem`'s doc comment.
/// Unlike `note`, there is no shadow-column pair to keep in sync yet:
/// `detail_plain` is simply the detail for now, so adding `detail_rtf` later
/// is an additive `ALTER TABLE` plus a derivation change, not a rework of
/// this schema or `task_fts`.
public enum TaskSchema {
    /// Migration name registered with GRDB's `DatabaseMigrator` in
    /// `NotebarStore`. A new migration alongside `NoteSchema.migrationName`
    /// and `OpenTabSchema.migrationName` — existing databases pick this up
    /// on next launch without recreating the file.
    public static let migrationName = "createTaskBoard"

    /// The one board v1 seeds. A fixed id (rather than a fresh UUID per
    /// migration run) is what makes the seed idempotent: `INSERT OR IGNORE`
    /// keys on it, so migrating twice — or seeding again after a partial
    /// failure — never inserts a second board.
    public static let defaultBoardID = "board-default"
    public static let queueColumnID = "column-queue"
    public static let workingColumnID = "column-working"
    public static let doneColumnID = "column-done"

    public static let createBoardTable = """
    CREATE TABLE board (
      id         TEXT PRIMARY KEY,
      name       TEXT NOT NULL,
      sort_order REAL NOT NULL
    )
    """

    public static let createBoardColumnTable = """
    CREATE TABLE board_column (
      id         TEXT PRIMARY KEY,
      board_id   TEXT NOT NULL REFERENCES board(id) ON DELETE CASCADE,
      name       TEXT NOT NULL,
      kind       TEXT NOT NULL,
      sort_order REAL NOT NULL,
      wip_limit  INTEGER
    )
    """

    public static let createTaskTable = """
    CREATE TABLE task (
      id           TEXT PRIMARY KEY,
      title        TEXT NOT NULL,
      detail_plain TEXT NOT NULL DEFAULT '',
      column_id    TEXT NOT NULL REFERENCES board_column(id),
      sort_order   REAL NOT NULL,
      priority     INTEGER NOT NULL DEFAULT 0,
      due_at       TEXT,
      completed_at TEXT,
      created_at   TEXT NOT NULL,
      updated_at   TEXT NOT NULL
    )
    """

    /// External-content FTS5 table over `task`, matching spec §5 exactly —
    /// see `NoteSchema.createNoteFTSTable` for why `content_rowid='rowid'`
    /// works with a TEXT primary key.
    public static let createTaskFTSTable = """
    CREATE VIRTUAL TABLE task_fts USING fts5(
      title,
      detail_plain,
      content='task',
      content_rowid='rowid'
    )
    """

    /// Standard FTS5 external-content sync triggers. `GRDBTaskRepository`
    /// always writes `title` and `detail_plain` together in the same row
    /// write, so these triggers fire within that same write and `task_fts`
    /// can never observe one column updated without the other.
    public static let taskFTSTriggers = """
    CREATE TRIGGER task_ai AFTER INSERT ON task BEGIN
      INSERT INTO task_fts(rowid, title, detail_plain) VALUES (new.rowid, new.title, new.detail_plain);
    END;
    CREATE TRIGGER task_ad AFTER DELETE ON task BEGIN
      INSERT INTO task_fts(task_fts, rowid, title, detail_plain) VALUES ('delete', old.rowid, old.title, old.detail_plain);
    END;
    CREATE TRIGGER task_au AFTER UPDATE ON task BEGIN
      INSERT INTO task_fts(task_fts, rowid, title, detail_plain) VALUES ('delete', old.rowid, old.title, old.detail_plain);
      INSERT INTO task_fts(rowid, title, detail_plain) VALUES (new.rowid, new.title, new.detail_plain);
    END;
    """

    /// Seeds the one board and its three columns (spec §6.3a's Queue /
    /// Working / Done) on first run. `INSERT OR IGNORE` against the fixed
    /// ids above makes this safe to run more than once — belt-and-braces
    /// alongside GRDB's own migration tracking, which already would not
    /// re-run this migration by name, so a database can never end up with
    /// duplicate seeded columns regardless of how migration ever changes.
    public static let seedDefaultBoardAndColumns = """
    INSERT OR IGNORE INTO board (id, name, sort_order)
      VALUES ('\(defaultBoardID)', 'Board', 0);
    INSERT OR IGNORE INTO board_column (id, board_id, name, kind, sort_order, wip_limit)
      VALUES
        ('\(queueColumnID)', '\(defaultBoardID)', 'Queue', '\(BoardColumn.backlogKind)', 0, NULL),
        ('\(workingColumnID)', '\(defaultBoardID)', 'Working', '\(BoardColumn.activeKind)', 1, NULL),
        ('\(doneColumnID)', '\(defaultBoardID)', 'Done', '\(BoardColumn.doneKind)', 2, NULL);
    """
}
