using System.Reflection;

namespace Notebar.App;

/// <summary>The app's own version, read from the executing assembly rather
/// than hand-maintained anywhere -- the same principle as the macOS build
/// reading <c>CFBundleShortVersionString</c>/<c>CFBundleVersion</c> from the
/// bundle instead of a separate constant, so it can never drift from what
/// <c>Directory.Build.props</c>'s <c>&lt;Version&gt;</c> actually produced.
/// Settings -> About and the diagnostics export both read this, so they can
/// never disagree with each other either.</summary>
internal static class AppVersion
{
    private static readonly Version? Assembly =
        System.Reflection.Assembly.GetExecutingAssembly().GetName().Version;

    /// <summary>"0.1.0" -- Major.Minor.Build, matching Directory.Build.props's
    /// Version property.</summary>
    internal static string ShortVersion =>
        Assembly is null ? "unknown" : $"{Assembly.Major}.{Assembly.Minor}.{Assembly.Build}";

    /// <summary>.NET has no separate "build number" the way CFBundleVersion is
    /// on macOS -- this is the assembly version's own Revision component, the
    /// closest analogue the SDK derives on its own from Directory.Build.props's
    /// Version rather than a second hand-maintained value.</summary>
    internal static string BuildNumber =>
        Assembly is null ? "unknown" : Assembly.Revision.ToString();

    /// <summary>"0.1.0 (0)" -- Settings -> About's display text.</summary>
    internal static string DisplayText => $"{ShortVersion} ({BuildNumber})";
}
