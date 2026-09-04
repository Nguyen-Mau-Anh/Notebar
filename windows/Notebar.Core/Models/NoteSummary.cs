namespace Notebar.Core.Models;

/// <summary>The lightweight projection the all-notes menu needs: just enough to
/// render a title and a relative timestamp.</summary>
/// <remarks>
/// Deliberately its own type rather than a Note with a placeholder body. The
/// repository never selects body_html for these — twenty notes with one
/// screenshot each would otherwise mean reading megabytes to draw a list of
/// names — and a distinct type is what keeps that honest. A Note with
/// BodyHtml: "" would compile at every call site whether or not the body was
/// actually loaded; NoteSummary has no body field at all.
/// </remarks>
public sealed record NoteSummary(string Id, string Title, DateTimeOffset UpdatedAt)
{
    /// <summary>Mirrors Note.DisplayTitle exactly — the all-notes menu must show
    /// "Untitled" the same way the tab strip does.</summary>
    public string DisplayTitle => string.IsNullOrEmpty(Title) ? "Untitled" : Title;
}
