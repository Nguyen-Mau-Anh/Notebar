using Microsoft.Data.Sqlite;
using Notebar.Core.Models;
using Notebar.Core.Repositories;

namespace Notebar.Store;

public sealed class SqliteTaskRepository(NotebarDatabase db) : ITaskRepository
{
    private const string Columns_ =
        "id, title, detail_plain, column_id, sort_order, priority, due_at, completed_at, created_at, updated_at";

    public IReadOnlyList<BoardColumn> Columns()
    {
        using var cmd = db.Connection.CreateCommand();
        cmd.CommandText = "SELECT id, board_id, name, kind, sort_order, wip_limit FROM board_column ORDER BY sort_order ASC";
        using var reader = cmd.ExecuteReader();
        var result = new List<BoardColumn>();
        while (reader.Read())
            result.Add(new BoardColumn(
                reader.GetString(0), reader.GetString(1), reader.GetString(2), reader.GetString(3),
                reader.GetDouble(4), reader.IsDBNull(5) ? null : reader.GetInt32(5)));
        return result;
    }

    public IReadOnlyList<TaskItem> All() => Query("""
        SELECT t.id, t.title, t.detail_plain, t.column_id, t.sort_order, t.priority,
               t.due_at, t.completed_at, t.created_at, t.updated_at
        FROM task t
        JOIN board_column c ON c.id = t.column_id
        ORDER BY c.sort_order ASC, t.sort_order ASC
        """);

    public TaskItem Create(string title, string columnId)
    {
        using var max = db.Connection.CreateCommand();
        max.CommandText = "SELECT MAX(sort_order) FROM task WHERE column_id = $col";
        max.Parameters.AddWithValue("$col", columnId);
        object? last = max.ExecuteScalar();
        double? previous = last is null or DBNull ? null : Convert.ToDouble(last);

        var task = TaskItem.New(title, columnId, SortOrder.Between(previous, null));

        using var cmd = db.Connection.CreateCommand();
        cmd.CommandText = $"""
            INSERT INTO task ({Columns_})
            VALUES ($id, $title, $detail, $col, $order, $priority, $due, $completed, $created, $updated)
            """;
        Bind(cmd, task);
        cmd.ExecuteNonQuery();

        // Not `task` itself: CreatedAt/UpdatedAt come from DateTimeOffset.UtcNow
        // at sub-millisecond precision, but Sql.ToText/FromText round-trips
        // through the database at millisecond precision. Returning the raw
        // in-memory value would make it compare unequal to every later Fetch of
        // the same row.
        return Fetch(task.Id)!;
    }

    public void Update(TaskItem task)
    {
        var stamped = task with { UpdatedAt = DateTimeOffset.UtcNow };
        using var cmd = db.Connection.CreateCommand();
        cmd.CommandText = """
            UPDATE task SET title = $title, detail_plain = $detail, column_id = $col,
                            sort_order = $order, priority = $priority, due_at = $due,
                            completed_at = $completed, created_at = $created, updated_at = $updated
            WHERE id = $id
            """;
        Bind(cmd, stamped);
        if (cmd.ExecuteNonQuery() == 0)
            throw new InvalidOperationException($"task {task.Id} does not exist");
    }

    public void Delete(string id)
    {
        using var cmd = db.Connection.CreateCommand();
        cmd.CommandText = "DELETE FROM task WHERE id = $id";
        cmd.Parameters.AddWithValue("$id", id);
        cmd.ExecuteNonQuery();
    }

    public TaskItem Move(string id, string columnId, string? beforeId, string? afterId)
    {
        var task = Fetch(id) ?? throw new InvalidOperationException($"task {id} does not exist");

        bool wasDone = IsDoneColumn(task.ColumnId);
        bool willBeDone = IsDoneColumn(columnId);

        // Entering Done stamps the completion time; leaving it clears it.
        // Reordering *within* Done keeps the original stamp — the completion time
        // is when the work finished, not when the card was last dragged.
        DateTimeOffset? completedAt = (wasDone, willBeDone) switch
        {
            (false, true) => DateTimeOffset.UtcNow,
            (true, false) => null,
            _ => task.CompletedAt,
        };

        double? before = beforeId is null ? null : OrderOf(beforeId);
        double? after = afterId is null ? null : OrderOf(afterId);

        var moved = task with
        {
            ColumnId = columnId,
            SortOrder = SortOrder.Between(before, after),
            CompletedAt = completedAt,
            UpdatedAt = DateTimeOffset.UtcNow,
        };

        using var cmd = db.Connection.CreateCommand();
        cmd.CommandText = """
            UPDATE task SET column_id = $col, sort_order = $order,
                            completed_at = $completed, updated_at = $updated
            WHERE id = $id
            """;
        cmd.Parameters.AddWithValue("$col", moved.ColumnId);
        cmd.Parameters.AddWithValue("$order", moved.SortOrder);
        cmd.Parameters.AddWithValue("$completed", Sql.ToDb(moved.CompletedAt));
        cmd.Parameters.AddWithValue("$updated", Sql.ToText(moved.UpdatedAt));
        cmd.Parameters.AddWithValue("$id", id);
        cmd.ExecuteNonQuery();

        return moved;
    }

    public IReadOnlyList<TaskItem> Search(string query)
    {
        string match = FtsQuery.Sanitize(query);
        if (match.Length == 0) return [];

        using var cmd = db.Connection.CreateCommand();
        cmd.CommandText = $"""
            SELECT {string.Join(", ", Columns_.Split(", ").Select(c => "t." + c))}
            FROM task_fts f
            JOIN task t ON t.rowid = f.rowid
            WHERE task_fts MATCH $q
            ORDER BY rank
            """;
        cmd.Parameters.AddWithValue("$q", match);
        using var reader = cmd.ExecuteReader();
        var result = new List<TaskItem>();
        while (reader.Read()) result.Add(Read(reader));
        return result;
    }

    // --- helpers ---

    private bool IsDoneColumn(string columnId) =>
        Columns().Any(c => c.Id == columnId && c.Kind == BoardColumn.DoneKind);

    private TaskItem? Fetch(string id)
    {
        using var cmd = db.Connection.CreateCommand();
        cmd.CommandText = $"SELECT {Columns_} FROM task WHERE id = $id";
        cmd.Parameters.AddWithValue("$id", id);
        using var reader = cmd.ExecuteReader();
        return reader.Read() ? Read(reader) : null;
    }

    private IReadOnlyList<TaskItem> Query(string sql)
    {
        using var cmd = db.Connection.CreateCommand();
        cmd.CommandText = sql;
        using var reader = cmd.ExecuteReader();
        var result = new List<TaskItem>();
        while (reader.Read()) result.Add(Read(reader));
        return result;
    }

    private static TaskItem Read(SqliteDataReader r) => new(
        r.GetString(0), r.GetString(1), r.GetString(2), r.GetString(3), r.GetDouble(4),
        r.GetInt32(5), r.IsDBNull(6) ? null : Sql.FromText(r.GetString(6)),
        r.IsDBNull(7) ? null : Sql.FromText(r.GetString(7)),
        Sql.FromText(r.GetString(8)), Sql.FromText(r.GetString(9)));

    private static void Bind(SqliteCommand cmd, TaskItem task)
    {
        cmd.Parameters.AddWithValue("$id", task.Id);
        cmd.Parameters.AddWithValue("$title", task.Title);
        cmd.Parameters.AddWithValue("$detail", task.DetailPlain);
        cmd.Parameters.AddWithValue("$col", task.ColumnId);
        cmd.Parameters.AddWithValue("$order", task.SortOrder);
        cmd.Parameters.AddWithValue("$priority", task.Priority);
        cmd.Parameters.AddWithValue("$due", Sql.ToDb(task.DueAt));
        cmd.Parameters.AddWithValue("$completed", Sql.ToDb(task.CompletedAt));
        cmd.Parameters.AddWithValue("$created", Sql.ToText(task.CreatedAt));
        cmd.Parameters.AddWithValue("$updated", Sql.ToText(task.UpdatedAt));
    }

    private double OrderOf(string id)
    {
        using var cmd = db.Connection.CreateCommand();
        cmd.CommandText = "SELECT sort_order FROM task WHERE id = $id";
        cmd.Parameters.AddWithValue("$id", id);
        object? value = cmd.ExecuteScalar();
        return value is null or DBNull
            ? throw new InvalidOperationException($"task {id} does not exist")
            : Convert.ToDouble(value);
    }
}
