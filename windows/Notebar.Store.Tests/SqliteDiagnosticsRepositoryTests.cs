using Microsoft.Data.Sqlite;
using Notebar.Store;
using Xunit;

namespace Notebar.Store.Tests;

public class SqliteDiagnosticsRepositoryTests : IDisposable
{
    private readonly TestDatabase _fixture = new();
    private readonly SqliteDiagnosticsRepository _repo;

    // Set only by the one test below that opens a real file. Cleaned up in
    // Dispose so this is the one test in the suite that touches disk and it
    // still leaves nothing behind.
    private string? _diskPath;

    public SqliteDiagnosticsRepositoryTests() => _repo = new SqliteDiagnosticsRepository(_fixture.Db);

    public void Dispose()
    {
        _fixture.Dispose();
        if (_diskPath is null) return;

        // Microsoft.Data.Sqlite pools connections, and on Windows the native
        // file handle outlives Dispose() — POSIX would let us unlink an open
        // file, Windows will not. Drain the pool, then retry: a temp file left
        // behind is not worth failing a test over.
        SqliteConnection.ClearAllPools();
        foreach (var candidate in new[] { _diskPath, _diskPath + "-wal", _diskPath + "-shm" })
            TryDelete(candidate);
    }

    private static void TryDelete(string path)
    {
        for (int attempt = 0; attempt < 10; attempt++)
        {
            try
            {
                if (File.Exists(path)) File.Delete(path);
                return;
            }
            catch (IOException)
            {
                Thread.Sleep(50);
            }
        }
    }

    /// The in-memory database (used here and by the app's degrade-to-in-memory
    /// fallback) has no file on disk to size, so both come back null rather
    /// than throwing.
    [Fact]
    public void TheInMemoryCaseReportsANullPathAndSize()
    {
        var snapshot = _repo.Snapshot();
        Assert.Null(snapshot.Path);
        Assert.Null(snapshot.SizeOnDisk);
    }

    /// The in-memory case above can't exercise SizeOnDisk's actual file-reading
    /// branch — Path is null by construction there, so the null assertion holds
    /// no matter what that branch does. A real on-disk database is the only way
    /// to prove it actually sums bytes.
    [Fact]
    public void ReportsTheRealPathAndSizeOnDisk()
    {
        _diskPath = Path.Combine(Path.GetTempPath(), $"notebar-diagnostics-{Guid.NewGuid()}.sqlite");
        using var db = NotebarDatabase.Open(_diskPath);
        new SqliteNoteRepository(db).Create();

        var snapshot = new SqliteDiagnosticsRepository(db).Snapshot();

        Assert.Equal(_diskPath, snapshot.Path);
        Assert.True(snapshot.SizeOnDisk > 0);
    }

    [Fact]
    public void MigrationListMatchesTheDatabases()
    {
        var snapshot = _repo.Snapshot();
        Assert.Equal(_fixture.Db.AppliedMigrations, snapshot.AppliedMigrations);
    }
}
