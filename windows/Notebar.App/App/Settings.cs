using Notebar.Core.Panel;

namespace Notebar.App;

/// <summary>The activation-timing settings PanelController reads on every
/// effect. A plain static holder, not a repository: the app fills it from
/// <c>IAppStateRepository</c> at launch and whenever Settings changes, so
/// PanelController never has to know a database exists.</summary>
/// <remarks>
/// Defaults to the same constants PanelMachine and PanelGeometry fall back to,
/// so a fresh install with no stored settings behaves identically to one with
/// them explicitly saved. Task 16 wires this to the database; until then every
/// build behaves exactly like the constants in <see cref="PanelTiming"/>.
/// </remarks>
internal static class Settings
{
    internal static double EdgeDwell { get; set; } = PanelTiming.EdgeDwell;
    internal static double ExitDwell { get; set; } = PanelTiming.ExitDwell;
    internal static double ExitSlop { get; set; } = PanelTiming.ExitSlop;
}
