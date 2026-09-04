namespace Notebar.Core.Models;

/// <summary>Whether a chip's target no longer exists.</summary>
/// <remarks>
/// This cannot be answered from the link table. Deleting a note or task cascades
/// and removes every link row that touches it, on either end — so by the time a
/// chip needs restyling, the row behind it is gone too. A tombstone is detectable
/// only by asking "does the target itself still exist," which callers answer once
/// for the whole document rather than once per chip.
///
/// Split out from the styling that actually paints a tombstone so the decision
/// is unit-testable without a WebView.
/// </remarks>
public static class LinkTombstone
{
    /// <summary>Null when <paramref name="url"/> is not a chip this app ever wrote
    /// — a foreign scheme, or a malformed notebar:// URL — mirroring
    /// <see cref="LinkUrl.Parse"/>, so a caller can tell "not a chip" apart from
    /// "a chip whose target is gone". True when it is a chip and
    /// <paramref name="existingTargets"/> does not contain its target.</summary>
    public static bool? IsTombstone(string url, IReadOnlySet<LinkTarget> existingTargets)
    {
        var target = LinkUrl.Parse(url);
        if (target is null) return null;
        return !existingTargets.Contains(target.Value);
    }
}
