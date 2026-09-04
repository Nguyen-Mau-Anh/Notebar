using Microsoft.UI.Xaml;

namespace Notebar.App;

public partial class App : Application
{
    private PanelWindow? _window;

    public App() => InitializeComponent();

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        _window = new PanelWindow();
        _window.Activate();
    }
}
