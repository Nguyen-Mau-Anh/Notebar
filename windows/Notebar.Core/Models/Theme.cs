namespace Notebar.Core.Models;

/// <summary>The user's appearance preference: a three-way choice between
/// following Windows' own appearance and pinning to one of its two modes.</summary>
public enum Theme { System, Light, Dark }

public static class ThemeExtensions
{
    /// <summary>The default: an overlay that floats above other apps should
    /// match them.</summary>
    public static Theme Default => Theme.System;

    /// <summary>Falls back to <see cref="Default"/> both when nothing has been
    /// saved and when the saved value is no longer recognised — someone
    /// hand-editing the database must get the default appearance back, not a
    /// crash.</summary>
    public static Theme Parse(string? raw) => raw switch
    {
        "light" => Theme.Light,
        "dark" => Theme.Dark,
        "system" => Theme.System,
        _ => Default,
    };

    public static string ToStorageString(this Theme theme) => theme switch
    {
        Theme.Light => "light",
        Theme.Dark => "dark",
        _ => "system",
    };
}
