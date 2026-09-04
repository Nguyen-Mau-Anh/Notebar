using Notebar.Core.Panel;
using Xunit;

namespace Notebar.Core.Tests;

public class PanelTimingTests
{
    /// The handle is the only visible target, so the activation strip must be
    /// exactly as wide as it. These drifting apart is how the affordance
    /// silently stopped working on macOS.
    [Fact]
    public void TriggerMatchesHandle()
    {
        Assert.Equal(PanelTiming.HandleWidth, PanelTiming.TriggerWidth);
    }

    /// Maximized must be wide enough for the tasks board's three columns to
    /// stop being unusably narrow. On a 1440-wide work area, half is 720.
    [Fact]
    public void MaximizedWidthReachesBoardBreakpoint()
    {
        const double workAreaWidth = 1440;
        double maximized = workAreaWidth * PanelTiming.MaximizedWidthFraction;
        Assert.True(maximized >= 600, $"maximized width {maximized} is below the board breakpoint");
        Assert.True(maximized > PanelTiming.PanelWidth, "maximized must be wider than the normal panel");
    }
}
