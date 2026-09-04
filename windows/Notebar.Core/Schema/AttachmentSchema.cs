namespace Notebar.Core.Schema;

/// <summary>Images pasted into notes, stored as rows rather than embedded in the
/// note body — see the Attachment model for why.</summary>
public static class AttachmentSchema
{
    public const string MigrationName = "createAttachment";

    public const string CreateAttachmentTable = """
        CREATE TABLE attachment (
          id         TEXT PRIMARY KEY,
          mime_type  TEXT NOT NULL,
          data       BLOB NOT NULL,
          width      INTEGER NOT NULL,
          height     INTEGER NOT NULL,
          created_at TEXT NOT NULL
        )
        """;
}
