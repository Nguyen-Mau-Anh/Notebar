using Notebar.Core.Models;

namespace Notebar.Core.Repositories;

/// <summary>Storage for small app-wide preferences: theme and the panel's
/// activation timings.</summary>
/// <remarks>
/// Every getter falls back to a default when nothing is stored or the stored
/// value does not parse, and clamps the panel timings to their designed range
/// when it parses but is out of bounds — a hand-edited database must never push
/// the panel further than the settings sliders could.
/// </remarks>
public interface IAppStateRepository
{
    Theme GetTheme();
    void SetTheme(Theme theme);

    double GetEdgeDwell();
    void SetEdgeDwell(double value);

    double GetExitDwell();
    void SetExitDwell(double value);

    double GetExitSlop();
    void SetExitSlop(double value);
}
