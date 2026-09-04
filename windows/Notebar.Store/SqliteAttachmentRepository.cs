using Microsoft.Data.Sqlite;
using Notebar.Core.Models;
using Notebar.Core.Repositories;

namespace Notebar.Store;

public sealed class SqliteAttachmentRepository(NotebarDatabase db) : IAttachmentRepository
{
    public Attachment Create(string mimeType, byte[] data, int width, int height)
    {
        var attachment = new Attachment(
            Guid.NewGuid().ToString(), mimeType, data, width, height, DateTimeOffset.UtcNow);

        using var cmd = db.Connection.CreateCommand();
        cmd.CommandText = """
            INSERT INTO attachment (id, mime_type, data, width, height, created_at)
            VALUES ($id, $mime, $data, $width, $height, $created)
            """;
        cmd.Parameters.AddWithValue("$id", attachment.Id);
        cmd.Parameters.AddWithValue("$mime", attachment.MimeType);
        cmd.Parameters.AddWithValue("$data", attachment.Data);
        cmd.Parameters.AddWithValue("$width", attachment.Width);
        cmd.Parameters.AddWithValue("$height", attachment.Height);
        cmd.Parameters.AddWithValue("$created", Sql.ToText(attachment.CreatedAt));
        cmd.ExecuteNonQuery();

        // Not `attachment` itself: CreatedAt comes from DateTimeOffset.UtcNow at
        // sub-millisecond precision, but Sql.ToText/FromText round-trips through
        // the database at millisecond precision.
        return Fetch(attachment.Id)!;
    }

    public Attachment? Fetch(string id)
    {
        using var cmd = db.Connection.CreateCommand();
        cmd.CommandText = "SELECT id, mime_type, data, width, height, created_at FROM attachment WHERE id = $id";
        cmd.Parameters.AddWithValue("$id", id);
        using var reader = cmd.ExecuteReader();
        if (!reader.Read()) return null;
        return new Attachment(
            reader.GetString(0), reader.GetString(1), (byte[])reader["data"],
            reader.GetInt32(3), reader.GetInt32(4), Sql.FromText(reader.GetString(5)));
    }

    /// <summary>Deletes every attachment row no note's body still references. See
    /// <see cref="IAttachmentRepository.DeleteOrphans"/> for why this takes no
    /// argument.</summary>
    public void DeleteOrphans()
    {
        using var cmd = db.Connection.CreateCommand();
        cmd.CommandText = """
            DELETE FROM attachment
            WHERE NOT EXISTS (
                SELECT 1 FROM note
                WHERE note.body_html LIKE '%/asset/' || attachment.id || '%')
            """;
        cmd.ExecuteNonQuery();
    }
}
