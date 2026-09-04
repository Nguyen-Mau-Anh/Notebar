using Microsoft.Data.Sqlite;
using Notebar.Core.Models;
using Notebar.Core.Repositories;

namespace Notebar.Store;

public sealed class SqliteNoteRepository(NotebarDatabase db) : INoteRepository
{
    private const string Columns =
        "id, title, body_html, body_plain, is_pinned, sort_order, created_at, updated_at";

    public IReadOnlyList<Note> All() =>
        Query($"SELECT {Columns} FROM note ORDER BY sort_order ASC");

    public IReadOnlyList<NoteSummary> Summaries()
    {
        // Deliberately does not select body_html. Twenty notes with one
        // screenshot each would otherwise mean reading megabytes to draw a
        // list of names.
        using var cmd = db.Connection.CreateCommand();
        cmd.CommandText = "SELECT id, title, updated_at FROM note ORDER BY sort_order ASC";
        using var reader = cmd.ExecuteReader();
        var result = new List<NoteSummary>();
        while (reader.Read())
            result.Add(new NoteSummary(reader.GetString(0), reader.GetString(1),
                                       Sql.FromText(reader.GetString(2))));
        return result;
    }

    public Note? Fetch(string id)
    {
        using var cmd = db.Connection.CreateCommand();
        cmd.CommandText = $"SELECT {Columns} FROM note WHERE id = $id";
        cmd.Parameters.AddWithValue("$id", id);
        using var reader = cmd.ExecuteReader();
        return reader.Read() ? Read(reader) : null;
    }

    public Note Create()
    {
        double last = ScalarDouble("SELECT MAX(sort_order) FROM note");
        var note = Note.New(SortOrder.Between(double.IsNaN(last) ? null : last, null));

        using var cmd = db.Connection.CreateCommand();
        cmd.CommandText = $"""
            INSERT INTO note ({Columns})
            VALUES ($id, $title, $html, $plain, $pinned, $order, $created, $updated)
            """;
        Bind(cmd, note);
        cmd.ExecuteNonQuery();

        // Not `note` itself: CreatedAt/UpdatedAt come from DateTimeOffset.UtcNow
        // at sub-millisecond precision, but Sql.ToText/FromText round-trips
        // through the database at millisecond precision. Returning the raw
        // in-memory value would make it compare unequal to every later Fetch of
        // the same row.
        return Fetch(note.Id)!;
    }

    public void Update(Note note)
    {
        var stamped = note with { UpdatedAt = DateTimeOffset.UtcNow };
        using var cmd = db.Connection.CreateCommand();
        cmd.CommandText = """
            UPDATE note SET title = $title, body_html = $html, body_plain = $plain,
                            is_pinned = $pinned, sort_order = $order,
                            created_at = $created, updated_at = $updated
            WHERE id = $id
            """;
        Bind(cmd, stamped);
        if (cmd.ExecuteNonQuery() == 0)
            throw new InvalidOperationException($"note {note.Id} does not exist");
    }

    public void Delete(string id)
    {
        using var cmd = db.Connection.CreateCommand();
        cmd.CommandText = "DELETE FROM note WHERE id = $id";
        cmd.Parameters.AddWithValue("$id", id);
        cmd.ExecuteNonQuery();
    }

    public Note Reorder(string id, string? beforeId, string? afterId)
    {
        double? before = beforeId is null ? null : OrderOf(beforeId);
        double? after = afterId is null ? null : OrderOf(afterId);
        double target = SortOrder.Between(before, after);

        using var cmd = db.Connection.CreateCommand();
        cmd.CommandText = "UPDATE note SET sort_order = $order WHERE id = $id";
        cmd.Parameters.AddWithValue("$order", target);
        cmd.Parameters.AddWithValue("$id", id);
        if (cmd.ExecuteNonQuery() == 0)
            throw new InvalidOperationException($"note {id} does not exist");

        return Fetch(id)!;
    }

    public IReadOnlyList<Note> Search(string query)
    {
        string match = FtsQuery.Sanitize(query);
        if (match.Length == 0) return [];

        using var cmd = db.Connection.CreateCommand();
        cmd.CommandText = $"""
            SELECT {string.Join(", ", Columns.Split(", ").Select(c => "n." + c))}
            FROM note_fts f
            JOIN note n ON n.rowid = f.rowid
            WHERE note_fts MATCH $q
            ORDER BY rank
            """;
        cmd.Parameters.AddWithValue("$q", match);
        using var reader = cmd.ExecuteReader();
        var result = new List<Note>();
        while (reader.Read()) result.Add(Read(reader));
        return result;
    }

    // --- helpers ---

    private IReadOnlyList<Note> Query(string sql)
    {
        using var cmd = db.Connection.CreateCommand();
        cmd.CommandText = sql;
        using var reader = cmd.ExecuteReader();
        var result = new List<Note>();
        while (reader.Read()) result.Add(Read(reader));
        return result;
    }

    private static Note Read(SqliteDataReader r) => new(
        r.GetString(0), r.GetString(1), r.GetString(2), r.GetString(3),
        Sql.FromText(r.GetString(6)), Sql.FromText(r.GetString(7)),
        r.GetDouble(5), r.GetInt64(4) != 0);

    private static void Bind(SqliteCommand cmd, Note note)
    {
        cmd.Parameters.AddWithValue("$id", note.Id);
        cmd.Parameters.AddWithValue("$title", note.Title);
        cmd.Parameters.AddWithValue("$html", note.BodyHtml);
        cmd.Parameters.AddWithValue("$plain", note.BodyPlain);
        cmd.Parameters.AddWithValue("$pinned", note.IsPinned ? 1 : 0);
        cmd.Parameters.AddWithValue("$order", note.SortOrder);
        cmd.Parameters.AddWithValue("$created", Sql.ToText(note.CreatedAt));
        cmd.Parameters.AddWithValue("$updated", Sql.ToText(note.UpdatedAt));
    }

    private double OrderOf(string id)
    {
        using var cmd = db.Connection.CreateCommand();
        cmd.CommandText = "SELECT sort_order FROM note WHERE id = $id";
        cmd.Parameters.AddWithValue("$id", id);
        object? value = cmd.ExecuteScalar();
        return value is null or DBNull
            ? throw new InvalidOperationException($"note {id} does not exist")
            : Convert.ToDouble(value);
    }

    private double ScalarDouble(string sql)
    {
        using var cmd = db.Connection.CreateCommand();
        cmd.CommandText = sql;
        object? value = cmd.ExecuteScalar();
        return value is null or DBNull ? double.NaN : Convert.ToDouble(value);
    }
}
