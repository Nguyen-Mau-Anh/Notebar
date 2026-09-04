using Microsoft.Data.Sqlite;

namespace Notebar.Store;

/// <summary>The one connection to the SQLite file, plus the migrator that brings
/// it to the current schema.</summary>
/// <remarks>
/// A single connection rather than a pool: every repository call is synchronous
/// and short, the app is single-user and single-process, and WAL mode plus one
/// connection is simpler to reason about than concurrency that buys nothing here.
/// Callers must not use this from more than one thread at a time; the app
/// serialises database work onto one background queue.
/// </remarks>
public sealed class NotebarDatabase : IDisposable
{
    public SqliteConnection Connection { get; }

    /// <summary>The database file's path, or null when running in memory.</summary>
    public string? Path { get; }

    private NotebarDatabase(SqliteConnection connection, string? path)
    {
        Connection = connection;
        Path = path;
    }

    public static NotebarDatabase Open(string path)
    {
        var directory = System.IO.Path.GetDirectoryName(path);
        if (!string.IsNullOrEmpty(directory)) System.IO.Directory.CreateDirectory(directory);

        var conn = new SqliteConnection(new SqliteConnectionStringBuilder
        {
            DataSource = path,
            Mode = SqliteOpenMode.ReadWriteCreate,
        }.ToString());
        conn.Open();
        var db = new NotebarDatabase(conn, path);
        db.Configure();
        db.Migrate();
        return db;
    }

    /// <summary>An in-memory database, for tests and for the app's degrade path
    /// when the on-disk store cannot be opened. Shared cache so the single
    /// connection keeps it alive.</summary>
    public static NotebarDatabase OpenInMemory()
    {
        var conn = new SqliteConnection("Data Source=:memory:");
        conn.Open();
        var db = new NotebarDatabase(conn, null);
        db.Configure();
        db.Migrate();
        return db;
    }

    private void Configure()
    {
        Execute("PRAGMA foreign_keys = ON");
        // WAL only applies to a file-backed database; harmless on :memory:.
        if (Path is not null) Execute("PRAGMA journal_mode = WAL");
        Execute("""
            CREATE TABLE IF NOT EXISTS schema_migration (
              name       TEXT PRIMARY KEY,
              applied_at TEXT NOT NULL
            )
            """);
    }

    /// <summary>Applies every registered migration this database has not already
    /// recorded, in order, each in its own transaction.</summary>
    public void Migrate()
    {
        var applied = AppliedMigrations.ToHashSet();
        foreach (var migration in Migrations.All)
        {
            if (applied.Contains(migration.Name)) continue;

            using var tx = Connection.BeginTransaction();
            foreach (var statement in migration.Statements)
            {
                using var cmd = Connection.CreateCommand();
                cmd.Transaction = tx;
                cmd.CommandText = statement;
                cmd.ExecuteNonQuery();
            }
            using (var record = Connection.CreateCommand())
            {
                record.Transaction = tx;
                record.CommandText =
                    "INSERT INTO schema_migration (name, applied_at) VALUES ($n, $t)";
                record.Parameters.AddWithValue("$n", migration.Name);
                record.Parameters.AddWithValue("$t", Sql.ToText(DateTimeOffset.UtcNow));
                record.ExecuteNonQuery();
            }
            tx.Commit();
        }
    }

    /// <summary>Every migration recorded as applied, in application order. Names
    /// only — this feeds diagnostics, which must never carry note content.</summary>
    public IReadOnlyList<string> AppliedMigrations
    {
        get
        {
            using var cmd = Connection.CreateCommand();
            cmd.CommandText = "SELECT name FROM schema_migration ORDER BY applied_at, rowid";
            using var reader = cmd.ExecuteReader();
            var names = new List<string>();
            while (reader.Read()) names.Add(reader.GetString(0));
            return names;
        }
    }

    private void Execute(string sql)
    {
        using var cmd = Connection.CreateCommand();
        cmd.CommandText = sql;
        cmd.ExecuteNonQuery();
    }

    public void Dispose() => Connection.Dispose();
}

/// <summary>Text conversions shared by every repository, so a date written by one
/// is readable by another.</summary>
public static class Sql
{
    /// <summary>ISO-8601 UTC. Sortable as text, which is what lets ORDER BY on a
    /// timestamp column mean what it says.</summary>
    public const string DateFormat = "yyyy-MM-ddTHH:mm:ss.fffZ";

    public static string ToText(DateTimeOffset value) =>
        value.ToUniversalTime().ToString(DateFormat, System.Globalization.CultureInfo.InvariantCulture);

    public static DateTimeOffset FromText(string value) =>
        DateTimeOffset.ParseExact(value, DateFormat,
            System.Globalization.CultureInfo.InvariantCulture,
            System.Globalization.DateTimeStyles.AssumeUniversal |
            System.Globalization.DateTimeStyles.AdjustToUniversal);

    public static object ToDb(DateTimeOffset? value) =>
        value is { } v ? ToText(v) : DBNull.Value;
}
