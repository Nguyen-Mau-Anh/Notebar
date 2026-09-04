using System.Globalization;
using Microsoft.Data.Sqlite;
using Notebar.Core.Models;
using Notebar.Core.Panel;
using Notebar.Core.Repositories;
using Notebar.Core.Schema;

namespace Notebar.Store;

public sealed class SqliteAppStateRepository(NotebarDatabase db) : IAppStateRepository
{
    public Theme GetTheme() => ThemeExtensions.Parse(Get(AppStateSchema.ThemeKey));

    public void SetTheme(Theme theme) => Set(AppStateSchema.ThemeKey, theme.ToStorageString());

    public double GetEdgeDwell() =>
        GetClamped(AppStateSchema.EdgeDwellKey, PanelTiming.EdgeDwell,
                   PanelTiming.EdgeDwellMin, PanelTiming.EdgeDwellMax);

    public void SetEdgeDwell(double value) => SetDouble(AppStateSchema.EdgeDwellKey, value);

    public double GetExitDwell() =>
        GetClamped(AppStateSchema.ExitDwellKey, PanelTiming.ExitDwell,
                   PanelTiming.ExitDwellMin, PanelTiming.ExitDwellMax);

    public void SetExitDwell(double value) => SetDouble(AppStateSchema.ExitDwellKey, value);

    public double GetExitSlop() =>
        GetClamped(AppStateSchema.ExitSlopKey, PanelTiming.ExitSlop,
                   PanelTiming.ExitSlopMin, PanelTiming.ExitSlopMax);

    public void SetExitSlop(double value) => SetDouble(AppStateSchema.ExitSlopKey, value);

    /// <summary>Falls back to the constant when nothing is stored or the stored
    /// text does not parse, and clamps when it parses but is out of range. A
    /// hand-edited database must never push the panel further than the sliders
    /// could.</summary>
    private double GetClamped(string key, double fallback, double min, double max)
    {
        string? raw = Get(key);
        return double.TryParse(raw, NumberStyles.Float, CultureInfo.InvariantCulture, out double v)
            ? PanelTiming.Clamp(v, min, max)
            : fallback;
    }

    private void SetDouble(string key, double value) =>
        Set(key, value.ToString(CultureInfo.InvariantCulture));

    private string? Get(string key)
    {
        using var cmd = db.Connection.CreateCommand();
        cmd.CommandText = "SELECT value FROM app_state WHERE key = $k";
        cmd.Parameters.AddWithValue("$k", key);
        return cmd.ExecuteScalar() as string;
    }

    private void Set(string key, string value)
    {
        using var cmd = db.Connection.CreateCommand();
        cmd.CommandText = "INSERT OR REPLACE INTO app_state (key, value) VALUES ($k, $v)";
        cmd.Parameters.AddWithValue("$k", key);
        cmd.Parameters.AddWithValue("$v", value);
        cmd.ExecuteNonQuery();
    }
}
