namespace Notebar.Store.Tests;

/// <summary>A fresh in-memory database per test. Nothing here touches disk, so
/// tests cannot leak state into each other or into the developer's real store.</summary>
public sealed class TestDatabase : IDisposable
{
    public NotebarDatabase Db { get; } = NotebarDatabase.OpenInMemory();
    public void Dispose() => Db.Dispose();
}
