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

    /// <summary>Deletes every attachment row whose id is not in
    /// <paramref name="referencedIds"/>. Called after a note body save, so an
    /// image the user deleted from a note stops occupying the database.</summary>
    public void DeleteUnreferenced(IReadOnlySet<string> referencedIds)
    {
        using var cmd = db.Connection.CreateCommand();
        cmd.CommandText = "SELECT id FROM attachment";
        var allIds = new List<string>();
        using (var reader = cmd.ExecuteReader())
            while (reader.Read()) allIds.Add(reader.GetString(0));

        foreach (var id in allIds)
        {
            if (referencedIds.Contains(id)) continue;
            using var delete = db.Connection.CreateCommand();
            delete.CommandText = "DELETE FROM attachment WHERE id = $id";
            delete.Parameters.AddWithValue("$id", id);
            delete.ExecuteNonQuery();
        }
    }
}
