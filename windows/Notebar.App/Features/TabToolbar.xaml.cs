using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Notebar.App.Features;

/// <summary>The 36pt toolbar row every content tab opens with (screen spec §2 "Tab
/// toolbar"): context on the left, primary action on the right, a hairline beneath. See
/// TabToolbar.xaml's own remarks -- this is a fixed, generic two-slot shell; RootPage
/// supplies the actual per-tab content (the Notes tab strip placeholder and its + and
/// chevron, the Tasks title and count and its +, the Settings title alone) as
/// LeftContent/RightContent, the same split the macOS build's generic
/// TabToolbar&lt;Left, Right&gt; used.</summary>
internal sealed partial class TabToolbar : UserControl
{
    internal static readonly DependencyProperty LeftContentProperty =
        DependencyProperty.Register(nameof(LeftContent), typeof(object), typeof(TabToolbar), new PropertyMetadata(null));

    internal static readonly DependencyProperty RightContentProperty =
        DependencyProperty.Register(nameof(RightContent), typeof(object), typeof(TabToolbar), new PropertyMetadata(null));

    internal TabToolbar()
    {
        InitializeComponent();
    }

    internal object? LeftContent
    {
        get => GetValue(LeftContentProperty);
        set => SetValue(LeftContentProperty, value);
    }

    internal object? RightContent
    {
        get => GetValue(RightContentProperty);
        set => SetValue(RightContentProperty, value);
    }
}
