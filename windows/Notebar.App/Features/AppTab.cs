namespace Notebar.App.Features;

/// <summary>The three top-level tabs, fixed order (screen spec §3: Notes, Tasks, Settings --
/// no fourth item, no bottom-anchored account row). Kept in Notebar.App rather than
/// Notebar.Core because it is UI vocabulary, not domain state -- the same split the macOS
/// app keeps between AppTab.swift (the app target) and NotebarCore.</summary>
internal enum AppTab
{
    Notes,
    Tasks,
    Settings,
}

/// <summary>Per-tab display facts the rail and the collapsed handle need. A pure lookup,
/// deliberately free of any WinUI type.</summary>
internal static class AppTabInfo
{
    internal static string Title(this AppTab tab) => tab switch
    {
        AppTab.Notes => "Notes",
        AppTab.Tasks => "Tasks",
        AppTab.Settings => "Settings",
        _ => throw new ArgumentOutOfRangeException(nameof(tab), tab, null),
    };

    /// <summary>The Segoe Fluent Icons glyph nearest the SF Symbol the screen spec names for
    /// this tab (§3's SF Symbol column). Windows has no SF Symbols and this task bundles no
    /// icon assets, so this is the closest built-in glyph rather than a pixel-identical
    /// match -- worth an eyes-on check once this can run on Windows.</summary>
    internal static string Glyph(this AppTab tab) => tab switch
    {
        AppTab.Notes => "",    // Document -- spec: note.text
        AppTab.Tasks => "",    // CheckList -- spec: checklist
        AppTab.Settings => "", // Setting (gear) -- spec: gearshape
        _ => throw new ArgumentOutOfRangeException(nameof(tab), tab, null),
    };
}
