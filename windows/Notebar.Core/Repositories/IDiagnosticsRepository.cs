using Notebar.Core.Models;

namespace Notebar.Core.Repositories;

/// <summary>Storage for the Settings → Data / Export Diagnostics snapshot.</summary>
public interface IDiagnosticsRepository
{
    /// <summary>A snapshot of facts about the on-disk store: its path, its size,
    /// and the list of applied migrations. Never note or task content.</summary>
    DatabaseDiagnostics Snapshot();
}
