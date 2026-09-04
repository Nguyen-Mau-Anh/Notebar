namespace Notebar.App.DesignSystem;

/// <summary>Code-behind for Tokens.xaml, needed only because it carries x:Class. Instantiated
/// as an object element (&lt;design:Tokens/&gt;) from RootPage's
/// ResourceDictionary.MergedDictionaries -- the same pattern App.xaml already uses for
/// XamlControlsResources -- rather than merged by a runtime "ms-appx:///" Source URI, so
/// resolving these tokens does not depend on package-resource lookup working the same way in
/// both the MSIX and the portable (unpackaged) build.</summary>
internal sealed partial class Tokens : Microsoft.UI.Xaml.ResourceDictionary
{
    internal Tokens()
    {
        InitializeComponent();
    }
}
