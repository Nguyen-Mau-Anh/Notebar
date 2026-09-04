namespace Notebar.Core.Schema;

using Notebar.Core.Models;

public static class TaskSchema
{
    public const string MigrationName = "createTaskBoard";

    /// <summary>Fixed ids rather than fresh GUIDs per migration run. That is what
    /// makes the seed idempotent: INSERT OR IGNORE keys on them, so seeding again
    /// after a partial failure never inserts a second board.</summary>
    public const string DefaultBoardId = "board-default";
    public const string QueueColumnId = "column-queue";
    public const string WorkingColumnId = "column-working";
    public const string DoneColumnId = "column-done";

    public const string CreateBoardTable = """
        CREATE TABLE board (
          id         TEXT PRIMARY KEY,
          name       TEXT NOT NULL,
          sort_order REAL NOT NULL
        )
        """;

    public const string CreateBoardColumnTable = """
        CREATE TABLE board_column (
          id         TEXT PRIMARY KEY,
          board_id   TEXT NOT NULL REFERENCES board(id) ON DELETE CASCADE,
          name       TEXT NOT NULL,
          kind       TEXT NOT NULL,
          sort_order REAL NOT NULL,
          wip_limit  INTEGER
        )
        """;

    public const string CreateTaskTable = """
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
        """;

    public const string CreateTaskFtsTable = """
        CREATE VIRTUAL TABLE task_fts USING fts5(
          title,
          detail_plain,
          content='task',
          content_rowid='rowid'
        )
        """;

    public const string TaskFtsTriggers = """
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
        """;

    public static string SeedBoard =>
        $"INSERT OR IGNORE INTO board (id, name, sort_order) VALUES ('{DefaultBoardId}', 'Board', 0)";

    public static string SeedColumns => $"""
        INSERT OR IGNORE INTO board_column (id, board_id, name, kind, sort_order, wip_limit)
        VALUES
          ('{QueueColumnId}',   '{DefaultBoardId}', 'Queue',   '{BoardColumn.BacklogKind}', 0, NULL),
          ('{WorkingColumnId}', '{DefaultBoardId}', 'Working', '{BoardColumn.ActiveKind}',  1, NULL),
          ('{DoneColumnId}',    '{DefaultBoardId}', 'Done',    '{BoardColumn.DoneKind}',    2, NULL)
        """;
}
