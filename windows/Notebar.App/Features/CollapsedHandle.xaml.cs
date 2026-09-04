using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;

namespace Notebar.App.Features;

/// <summary>The 30x56dip handle the panel collapses to (screen spec §2). See
/// CollapsedHandle.xaml's own remarks.</summary>
internal sealed partial class CollapsedHandle : UserControl
{
    internal AppTab Tab { get; private set; } = AppTab.Notes;

    internal CollapsedHandle()
    {
        InitializeComponent();
        SetTab(AppTab.Notes);
    }

    /// <summary>Shows the given tab's glyph and updates the accessible name. Called by
    /// RootPage on construction and every time PanelViewModel.Selection changes -- the
    /// handle must always reflect the *currently* selected tab, not whichever tab was active
    /// the last time the panel was visible.</summary>
    internal void SetTab(AppTab tab)
    {
        Tab = tab;
        IconOff.Glyph = tab.Glyph();
        IconOn.Glyph = tab.Glyph();
        AutomationProperties.SetName(Root, tab.Title());
    }

    private void OnPointerEntered(object sender, PointerRoutedEventArgs e)
    {
        IconOff.Visibility = Visibility.Collapsed;
        IconOn.Visibility = Visibility.Visible;
    }

    private void OnPointerExited(object sender, PointerRoutedEventArgs e)
    {
        IconOff.Visibility = Visibility.Visible;
        IconOn.Visibility = Visibility.Collapsed;
    }
}
