using Notebar.Core.Models;
using Notebar.Core.Repositories;

namespace Notebar.Store;

/// <summary>Unlike the other repositories, this one reads db.Path directly
/// rather than deriving it — there is no column in any table that records where
/// the database file that holds it lives.</summary>
public sealed class SqliteDiagnosticsRepository(NotebarDatabase db) : IDiagnosticsRepository
{
    public DatabaseDiagnostics Snapshot() =>
        new(db.Path, SizeOnDisk(db.Path), db.AppliedMigrations);

    /// <summary>The main database file's size plus any -wal/-shm sidecar files
    /// SQLite may have alongside it, so the reported number matches what a file
    /// browser would show for "the database" rather than just the main file.
    /// Null when there is no on-disk path, or when any read throws.</summary>
    private static long? SizeOnDisk(string? path)
    {
        if (path is null) return null;
        try
        {
            long total = 0;
            foreach (var candidate in new[] { path, path + "-wal", path + "-shm" })
            {
                var info = new System.IO.FileInfo(candidate);
                if (info.Exists) total += info.Length;
            }
            return total;
        }
        catch
        {
            return null;
        }
    }
}
