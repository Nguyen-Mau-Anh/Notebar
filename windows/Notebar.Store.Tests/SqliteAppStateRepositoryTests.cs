using Notebar.Core.Models;
using Notebar.Core.Panel;
using Notebar.Core.Schema;
using Notebar.Store;
using Xunit;

namespace Notebar.Store.Tests;

public class SqliteAppStateRepositoryTests : IDisposable
{
    private readonly TestDatabase _fixture = new();
    private readonly SqliteAppStateRepository _repo;

    public SqliteAppStateRepositoryTests() => _repo = new SqliteAppStateRepository(_fixture.Db);
    public void Dispose() => _fixture.Dispose();

    [Fact]
    public void ThemeDefaultsToSystem() => Assert.Equal(Theme.System, _repo.GetTheme());

    [Theory]
    [InlineData(Theme.Light)]
    [InlineData(Theme.Dark)]
    [InlineData(Theme.System)]
    public void ThemeRoundTrips(Theme theme)
    {
        _repo.SetTheme(theme);
        Assert.Equal(theme, _repo.GetTheme());
    }

    /// Someone hand-editing the database must get the default appearance back,
    /// not a crash.
    [Fact]
    public void AnUnrecognisedThemeFallsBackToTheDefault()
    {
        WriteRaw(AppStateSchema.ThemeKey, "solarized");
        Assert.Equal(Theme.System, _repo.GetTheme());
    }

    [Fact]
    public void TimingsDefaultToTheirConstants()
    {
        Assert.Equal(PanelTiming.EdgeDwell, _repo.GetEdgeDwell());
        Assert.Equal(PanelTiming.ExitDwell, _repo.GetExitDwell());
        Assert.Equal(PanelTiming.ExitSlop, _repo.GetExitSlop());
    }

    [Fact]
    public void TimingsRoundTrip()
    {
        _repo.SetEdgeDwell(0.3);
        _repo.SetExitDwell(1.0);
        _repo.SetExitSlop(50);
        Assert.Equal(0.3, _repo.GetEdgeDwell());
        Assert.Equal(1.0, _repo.GetExitDwell());
        Assert.Equal(50, _repo.GetExitSlop());
    }

    /// A stored value out of range is clamped on read, not trusted. The settings
    /// slider cannot produce these; a text editor can.
    [Fact]
    public void OutOfRangeStoredValuesAreClampedOnRead()
    {
        WriteRaw(AppStateSchema.EdgeDwellKey, "99");
        WriteRaw(AppStateSchema.ExitDwellKey, "0");
        WriteRaw(AppStateSchema.ExitSlopKey, "-5");

        Assert.Equal(PanelTiming.EdgeDwellMax, _repo.GetEdgeDwell());
        // Zero would make the panel collapse the instant the cursor leaves,
        // which is the hostile behaviour the whole suppression policy prevents.
        Assert.Equal(PanelTiming.ExitDwellMin, _repo.GetExitDwell());
        Assert.Equal(PanelTiming.ExitSlopMin, _repo.GetExitSlop());
    }

    [Fact]
    public void AnUnparseableTimingFallsBackToItsConstant()
    {
        WriteRaw(AppStateSchema.EdgeDwellKey, "soon");
        Assert.Equal(PanelTiming.EdgeDwell, _repo.GetEdgeDwell());
    }

    /// Written with the invariant culture, so a machine set to a comma-decimal
    /// locale reads back what another machine wrote.
    [Fact]
    public void TimingsUseInvariantNumberFormatting()
    {
        _repo.SetEdgeDwell(0.25);
        Assert.Equal("0.25", ReadRaw(AppStateSchema.EdgeDwellKey));
    }

    private void WriteRaw(string key, string value)
    {
        using var cmd = _fixture.Db.Connection.CreateCommand();
        cmd.CommandText = "INSERT OR REPLACE INTO app_state (key, value) VALUES ($k, $v)";
        cmd.Parameters.AddWithValue("$k", key);
        cmd.Parameters.AddWithValue("$v", value);
        cmd.ExecuteNonQuery();
    }

    private string? ReadRaw(string key)
    {
        using var cmd = _fixture.Db.Connection.CreateCommand();
        cmd.CommandText = "SELECT value FROM app_state WHERE key = $k";
        cmd.Parameters.AddWithValue("$k", key);
        return cmd.ExecuteScalar() as string;
    }
}
