namespace Notebar.App.Features.Notes;

/// <summary>Formats a timestamp as a short relative string for the all-notes menu ("just
/// now", "5m ago", "3h ago", "2d ago", falling back to a plain date once it is far enough in
/// the past that a relative string stops being useful).</summary>
internal static class RelativeTime
{
    internal static string Format(DateTimeOffset value) => Format(value, DateTimeOffset.UtcNow);

    internal static string Format(DateTimeOffset value, DateTimeOffset now)
    {
        TimeSpan elapsed = now - value;
        if (elapsed < TimeSpan.Zero) elapsed = TimeSpan.Zero;

        if (elapsed < TimeSpan.FromSeconds(60)) return "just now";
        if (elapsed < TimeSpan.FromMinutes(60)) return $"{(int)elapsed.TotalMinutes}m ago";
        if (elapsed < TimeSpan.FromHours(24)) return $"{(int)elapsed.TotalHours}h ago";
        if (elapsed < TimeSpan.FromDays(7)) return $"{(int)elapsed.TotalDays}d ago";

        return value.ToLocalTime().ToString("MMM d", System.Globalization.CultureInfo.InvariantCulture);
    }
}
