using Microsoft.UI.Xaml;
using Notebar.Core.Panel;

namespace Notebar.App;

public sealed partial class PanelWindow : Window
{
    public PanelWindow()
    {
        InitializeComponent();
        Title = "Notebar";
        Placeholder.Text = $"Notebar — panel width {PanelTiming.PanelWidth}";
    }
}
