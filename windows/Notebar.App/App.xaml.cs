using Microsoft.UI.Xaml;
using Notebar.App.Interop;
using Notebar.App.Panel;
using Notebar.Core.Geometry;
using Notebar.Core.Panel;

namespace Notebar.App;

public partial class App : Application
{
    private PanelWindow? _window;

    public App() => InitializeComponent();

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        _window = new PanelWindow();

        var cursor = NativeMethods.GetCursorPos(out var pt)
            ? new PanelPoint(pt.X, pt.Y)
            : new PanelPoint(0, 0);
        var workArea = MonitorInfo.WorkAreaContaining(cursor, out double scale);
        var workAreaDips = new PanelRect(
            workArea.X / scale, workArea.Y / scale,
            workArea.Width / scale, workArea.Height / scale);

        _window.ApplyFrame(PanelGeometry.Collapsed(workAreaDips), scale);
        _window.ShowWithoutActivating();
    }
}
