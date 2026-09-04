using Microsoft.Data.Sqlite;
using Notebar.Core.Models;
using Notebar.Core.Repositories;

namespace Notebar.Store;

public sealed class SqliteOpenTabRepository(NotebarDatabase db) : IOpenTabRepository
{
    public IReadOnlyList<OpenTab> All()
    {
        using var cmd = db.Connection.CreateCommand();
        cmd.CommandText = "SELECT id, kind, ref_id, sort_order, is_active FROM open_tab ORDER BY sort_order ASC";
        using var reader = cmd.ExecuteReader();
        var result = new List<OpenTab>();
        while (reader.Read())
            result.Add(new OpenTab(
                reader.GetString(0), reader.GetString(1), reader.GetString(2),
                reader.GetDouble(3), reader.GetInt64(4) != 0));
        return result;
    }

    /// <summary>Deletes and reinserts inside one transaction. The strip is a
    /// handful of rows and changes only on open, close, reorder, and select,
    /// never per keystroke, so a full replace is simpler than diffing and cheap
    /// enough not to matter.</summary>
    public void ReplaceAll(IReadOnlyList<OpenTab> tabs)
    {
        using var tx = db.Connection.BeginTransaction();

        using (var delete = db.Connection.CreateCommand())
        {
            delete.Transaction = tx;
            delete.CommandText = "DELETE FROM open_tab";
            delete.ExecuteNonQuery();
        }

        foreach (var tab in tabs)
        {
            using var insert = db.Connection.CreateCommand();
            insert.Transaction = tx;
            insert.CommandText = """
                INSERT INTO open_tab (id, kind, ref_id, sort_order, is_active)
                VALUES ($id, $kind, $ref, $order, $active)
                """;
            insert.Parameters.AddWithValue("$id", tab.Id);
            insert.Parameters.AddWithValue("$kind", tab.Kind);
            insert.Parameters.AddWithValue("$ref", tab.RefId);
            insert.Parameters.AddWithValue("$order", tab.SortOrder);
            insert.Parameters.AddWithValue("$active", tab.IsActive ? 1 : 0);
            insert.ExecuteNonQuery();
        }

        tx.Commit();
    }
}
