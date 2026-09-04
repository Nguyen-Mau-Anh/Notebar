namespace Notebar.Core.Schema;

/// <summary>The generic edge table covering note→task, task→note, note→note, and
/// task→task, with backlinks as the reverse query on idx_link_dst.</summary>
public static class LinkSchema
{
    public const string MigrationName = "createLink";

    public const string CreateLinkTable = """
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
        """;

    public const string CreateSrcIndex = "CREATE INDEX idx_link_src ON link(src_type, src_id)";

    /// <summary>What makes backlinks a cheap reverse query. Created alongside the
    /// table even though nothing reads it yet: adding an index to a table that
    /// already holds rows is the expensive retrofit; adding it here costs nothing.</summary>
    public const string CreateDstIndex = "CREATE INDEX idx_link_dst ON link(dst_type, dst_id)";

    /// <summary>Two triggers, not one foreign key, because link has no real
    /// foreign key to either note or task — the same row's dst_id might belong to
    /// either table depending on dst_type, which ON DELETE CASCADE cannot express.
    ///
    /// Cascading rather than leaving dangling rows: a link pointing at an id that
    /// can never resolve again is indistinguishable from a bug, and tombstones do
    /// not need the row — a tombstone only needs the *target* to be gone, which it
    /// already is.</summary>
    public const string CascadeOnNoteDelete = """
        CREATE TRIGGER link_cleanup_note_delete AFTER DELETE ON note BEGIN
          DELETE FROM link WHERE (src_type = 'note' AND src_id = old.id) OR (dst_type = 'note' AND dst_id = old.id);
        END;
        """;

    public const string CascadeOnTaskDelete = """
        CREATE TRIGGER link_cleanup_task_delete AFTER DELETE ON task BEGIN
          DELETE FROM link WHERE (src_type = 'task' AND src_id = old.id) OR (dst_type = 'task' AND dst_id = old.id);
        END;
        """;
}
