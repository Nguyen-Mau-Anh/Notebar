using Microsoft.Data.Sqlite;
using Notebar.Core.Schema;
using Notebar.Store;
using Xunit;

namespace Notebar.Store.Tests;

public class MigrationTests
{
    /// FTS5 is a compile-time option in SQLite. Microsoft.Data.Sqlite bundles
    /// e_sqlite3, which is expected to include it — but if that expectation is
    /// ever wrong, every note migration fails on a user's machine rather than
    /// here. This is the cheapest possible place to find out.
    [Fact]
    public void Fts5IsAvailable()
    {
        using var conn = new SqliteConnection("Data Source=:memory:");
        conn.Open();
        using var cmd = conn.CreateCommand();
        cmd.CommandText = "CREATE VIRTUAL TABLE probe USING fts5(body)";
        cmd.ExecuteNonQuery();  // throws if FTS5 is not compiled in
    }

    [Fact]
    public void OpeningAppliesEveryMigrationInOrder()
    {
        using var db = NotebarDatabase.OpenInMemory();
        Assert.Equal(
            new[]
            {
                NoteSchema.MigrationName,
                OpenTabSchema.MigrationName,
                TaskSchema.MigrationName,
                AppStateSchema.MigrationName,
                LinkSchema.MigrationName,
                AttachmentSchema.MigrationName,
            },
            db.AppliedMigrations);
    }

    [Fact]
    public void MigratingTwiceIsANoOp()
    {
        using var db = NotebarDatabase.OpenInMemory();
        int before = db.AppliedMigrations.Count;
        db.Migrate();
        Assert.Equal(before, db.AppliedMigrations.Count);
    }

    [Fact]
    public void ForeignKeysAreEnforced()
    {
        using var db = NotebarDatabase.OpenInMemory();
        using var cmd = db.Connection.CreateCommand();
        cmd.CommandText = "PRAGMA foreign_keys";
        Assert.Equal(1L, Convert.ToInt64(cmd.ExecuteScalar()));
    }
}
