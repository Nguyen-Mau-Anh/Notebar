namespace Notebar.Core.Schema;

/// <summary>A generic key/value store, so every future small preference reuses
/// this one table instead of adding one of its own.</summary>
public static class AppStateSchema
{
    public const string MigrationName = "createAppState";

    public const string ThemeKey = "theme";

    /// <summary>Named after the constant each overrides, not the UI label, since
    /// the label ("Open delay"/"Close delay"/"Edge tolerance") is free to change
    /// without touching what is already on disk.</summary>
    public const string EdgeDwellKey = "edgeDwell";
    public const string ExitDwellKey = "exitDwell";
    public const string ExitSlopKey = "exitSlop";

    public const string CreateAppStateTable = """
        CREATE TABLE app_state (
          key   TEXT PRIMARY KEY,
          value TEXT NOT NULL
        )
        """;
}
