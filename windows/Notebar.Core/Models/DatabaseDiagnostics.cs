namespace Notebar.Core.Models;

/// <summary>A snapshot of facts about the on-disk store, for Settings → Data and
/// Export Diagnostics.</summary>
/// <remarks>
/// Every field here is a fact *about* the database — a path, a byte count, a list
/// of migration names — never a row of user content, so this type is structurally
/// incapable of carrying a note's title or body even by accident.
/// </remarks>
public sealed record DatabaseDiagnostics(
    /// <summary>Where the database file lives, or null when running on the
    /// in-memory fallback.</summary>
    string? Path,
    /// <summary>Size on disk in bytes including any -wal and -shm sidecars, or
    /// null if it could not be read.</summary>
    long? SizeOnDisk,
    /// <summary>The name of every migration recorded as applied, in order. Names
    /// only — never the rows a migration touched.</summary>
    IReadOnlyList<string> AppliedMigrations);
