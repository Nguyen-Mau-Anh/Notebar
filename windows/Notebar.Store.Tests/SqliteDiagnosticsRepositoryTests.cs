using Notebar.Store;
using Xunit;

namespace Notebar.Store.Tests;

public class SqliteDiagnosticsRepositoryTests : IDisposable
{
    private readonly TestDatabase _fixture = new();
    private readonly SqliteDiagnosticsRepository _repo;

    public SqliteDiagnosticsRepositoryTests() => _repo = new SqliteDiagnosticsRepository(_fixture.Db);
    public void Dispose() => _fixture.Dispose();

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

    [Fact]
    public void MigrationListMatchesTheDatabases()
    {
        var snapshot = _repo.Snapshot();
        Assert.Equal(_fixture.Db.AppliedMigrations, snapshot.AppliedMigrations);
    }
}
