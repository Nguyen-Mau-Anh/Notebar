using Microsoft.Data.Sqlite;
using Notebar.Core.Models;
using Notebar.Core.Repositories;

namespace Notebar.Store;

public sealed class SqliteLinkRepository(NotebarDatabase db) : ILinkRepository
{
    public Link Create(Link link)
    {
        using var cmd = db.Connection.CreateCommand();
        // OR IGNORE: chips are inserted by typing, and typing the same reference
        // twice is normal, not an error the user should ever see.
        cmd.CommandText = """
            INSERT OR IGNORE INTO link (id, src_type, src_id, dst_type, dst_id, kind, created_at)
            VALUES ($id, $st, $si, $dt, $di, $kind, $created)
            """;
        Bind(cmd, link);
        cmd.ExecuteNonQuery();

        // Not `link` itself, and not necessarily the row this call just wrote:
        // OR IGNORE means a duplicate edge leaves the *existing* row in place,
        // so this always reports whichever row now satisfies the unique
        // constraint. Re-fetching also round-trips CreatedAt through
        // Sql.ToText/FromText's millisecond precision — returning the raw
        // in-memory value would make it compare unequal to every later
        // Outgoing()/Incoming() read of the same row.
        return FetchByNaturalKey(link)!;
    }

    /// <summary>Inserts the link and saves the note's body in one transaction, so
    /// a chip's markup and the row behind it are always committed together — a
    /// crash between the two can never leave one without the other.</summary>
    public Link CreateSavingNoteBody(Link link, string noteId, string bodyHtml, string bodyPlain)
    {
        using var tx = db.Connection.BeginTransaction();

        using (var save = db.Connection.CreateCommand())
        {
            save.Transaction = tx;
            save.CommandText = """
                UPDATE note SET body_html = $html, body_plain = $plain, updated_at = $updated
                WHERE id = $id
                """;
            save.Parameters.AddWithValue("$html", bodyHtml);
            save.Parameters.AddWithValue("$plain", bodyPlain);
            save.Parameters.AddWithValue("$updated", Sql.ToText(DateTimeOffset.UtcNow));
            save.Parameters.AddWithValue("$id", noteId);
            if (save.ExecuteNonQuery() == 0)
                throw new InvalidOperationException($"note {noteId} does not exist");
        }

        using (var insert = db.Connection.CreateCommand())
        {
            insert.Transaction = tx;
            insert.CommandText = """
                INSERT OR IGNORE INTO link (id, src_type, src_id, dst_type, dst_id, kind, created_at)
                VALUES ($id, $st, $si, $dt, $di, $kind, $created)
                """;
            Bind(insert, link);
            insert.ExecuteNonQuery();
        }

        tx.Commit();
        return FetchByNaturalKey(link)!;
    }

    public void Delete(string id)
    {
        using var cmd = db.Connection.CreateCommand();
        cmd.CommandText = "DELETE FROM link WHERE id = $id";
        cmd.Parameters.AddWithValue("$id", id);
        cmd.ExecuteNonQuery();
    }

    public IReadOnlyList<Link> Outgoing(LinkTarget from) => Query(
        "SELECT id, src_type, src_id, dst_type, dst_id, kind, created_at FROM link WHERE src_type = $t AND src_id = $i",
        from);

    public IReadOnlyList<Link> Incoming(LinkTarget to) => Query(
        "SELECT id, src_type, src_id, dst_type, dst_id, kind, created_at FROM link WHERE dst_type = $t AND dst_id = $i",
        to);

    /// <summary>Every note and task id that still exists, as one set. Called once
    /// per note load rather than once per chip, which is what keeps the tombstone
    /// check to a set lookup.</summary>
    public IReadOnlySet<LinkTarget> ExistingTargets()
    {
        var targets = new HashSet<LinkTarget>();
        using var cmd = db.Connection.CreateCommand();
        cmd.CommandText = """
            SELECT 'note', id FROM note
            UNION ALL
            SELECT 'task', id FROM task
            """;
        using var reader = cmd.ExecuteReader();
        while (reader.Read())
        {
            var type = LinkEntityTypeExtensions.Parse(reader.GetString(0));
            if (type is { } t) targets.Add(new LinkTarget(t, reader.GetString(1)));
        }
        return targets;
    }

    // --- helpers ---

    /// <summary>Looks a link up by the same (src, dst, kind) tuple the table's
    /// UNIQUE constraint keys on, rather than by id — the row Create/
    /// CreateSavingNoteBody must report back is whichever one now satisfies
    /// that constraint, which after an OR IGNORE is not always the row just
    /// inserted.</summary>
    private Link? FetchByNaturalKey(Link link)
    {
        using var cmd = db.Connection.CreateCommand();
        cmd.CommandText = """
            SELECT id, src_type, src_id, dst_type, dst_id, kind, created_at FROM link
            WHERE src_type = $st AND src_id = $si AND dst_type = $dt AND dst_id = $di AND kind = $kind
            """;
        cmd.Parameters.AddWithValue("$st", link.SrcType.ToStorageString());
        cmd.Parameters.AddWithValue("$si", link.SrcId);
        cmd.Parameters.AddWithValue("$dt", link.DstType.ToStorageString());
        cmd.Parameters.AddWithValue("$di", link.DstId);
        cmd.Parameters.AddWithValue("$kind", link.Kind);
        using var reader = cmd.ExecuteReader();
        return reader.Read() ? Read(reader) : null;
    }

    private IReadOnlyList<Link> Query(string sql, LinkTarget target)
    {
        using var cmd = db.Connection.CreateCommand();
        cmd.CommandText = sql;
        cmd.Parameters.AddWithValue("$t", target.Type.ToStorageString());
        cmd.Parameters.AddWithValue("$i", target.Id);
        using var reader = cmd.ExecuteReader();
        var result = new List<Link>();
        while (reader.Read()) result.Add(Read(reader));
        return result;
    }

    private static Link Read(SqliteDataReader r) => new(
        r.GetString(0),
        LinkEntityTypeExtensions.Parse(r.GetString(1))!.Value, r.GetString(2),
        LinkEntityTypeExtensions.Parse(r.GetString(3))!.Value, r.GetString(4),
        r.GetString(5), Sql.FromText(r.GetString(6)));

    private static void Bind(SqliteCommand cmd, Link link)
    {
        cmd.Parameters.AddWithValue("$id", link.Id);
        cmd.Parameters.AddWithValue("$st", link.SrcType.ToStorageString());
        cmd.Parameters.AddWithValue("$si", link.SrcId);
        cmd.Parameters.AddWithValue("$dt", link.DstType.ToStorageString());
        cmd.Parameters.AddWithValue("$di", link.DstId);
        cmd.Parameters.AddWithValue("$kind", link.Kind);
        cmd.Parameters.AddWithValue("$created", Sql.ToText(link.CreatedAt));
    }
}
