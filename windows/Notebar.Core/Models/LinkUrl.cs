namespace Notebar.Core.Models;

/// <summary>The notebar://note/&lt;id&gt; and notebar://task/&lt;id&gt; scheme
/// every link chip carries.</summary>
/// <remarks>
/// Lives here, not in the app, so chip insertion (building the URL) and click
/// handling (parsing it back) share exactly one codec rather than two that can
/// drift. Works in plain strings rather than System.Uri: the core takes no
/// dependency on System.Net, and the WebView2 bridge exchanges these as strings
/// in both directions regardless.
/// </remarks>
public static class LinkUrl
{
    public const string Scheme = "notebar";

    public static string Build(LinkEntityType type, string id) =>
        $"{Scheme}://{type.ToStorageString()}/{id}";

    public static string Build(LinkTarget target) => Build(target.Type, target.Id);

    /// <summary>The inverse of <see cref="Build(LinkEntityType, string)"/>. Null for
    /// anything this type never produced — a link to a scheme this app does not
    /// own, or a malformed notebar:// URL — so a click on a chip whose target
    /// cannot be parsed does nothing rather than crashing.</summary>
    public static LinkTarget? Parse(string url)
    {
        const string prefix = Scheme + "://";
        if (string.IsNullOrEmpty(url) || !url.StartsWith(prefix, StringComparison.Ordinal))
            return null;

        string rest = url[prefix.Length..];
        int slash = rest.IndexOf('/');
        if (slash <= 0) return null;

        var type = LinkEntityTypeExtensions.Parse(rest[..slash]);
        if (type is null) return null;

        string id = rest[(slash + 1)..];
        if (id.Length == 0) return null;

        return new LinkTarget(type.Value, id);
    }
}
