namespace Notebar.Core.Models;

/// <summary>A single note.</summary>
/// <remarks>
/// BodyHtml is what the contenteditable editor round-trips; BodyPlain is the
/// plain-text shadow column FTS5 actually indexes, regenerated alongside
/// BodyHtml every time it changes so the two can never drift. Both live on
/// Note itself, and whoever holds the live document derives BodyPlain from it
/// and sets both fields together.
/// </remarks>
public sealed record Note(
    string Id,
    string Title,
    string BodyHtml,
    string BodyPlain,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt,
    double SortOrder,
    bool IsPinned)
{
    public static Note New(double sortOrder)
    {
        var now = DateTimeOffset.UtcNow;
        return new Note(Guid.NewGuid().ToString(), "Untitled", "", "", now, now, sortOrder, false);
    }

    /// <summary>The tab strip's label. Title is a stored, user-editable column —
    /// it does not track the body in any way, so typing in a note never changes
    /// its tab.</summary>
    public string DisplayTitle => string.IsNullOrEmpty(Title) ? "Untitled" : Title;

    /// <summary>Whether the note is exactly as it was created. Such a note carries
    /// no information the user typed, so closing its tab deletes it outright
    /// rather than leaving a contentless row cluttering the all-notes menu. A
    /// note with a title or a body is the user's actual content, and closing a
    /// tab must never destroy that.</summary>
    /// <remarks>
    /// Checks BodyPlain, not BodyHtml, for text content. An "empty" editor
    /// document still serializes to markup like &lt;p&gt;&lt;br&gt;&lt;/p&gt;, so a
    /// check against BodyHtml would never be true for a real note and this
    /// predicate would quietly stop working the moment the editor landed.
    /// BodyPlain is exactly the visible-text shadow that already answers "is
    /// there anything here."
    ///
    /// Also checks for an image. BodyPlain is empty for a note whose only content
    /// is a pasted screenshot, because an img contributes no text — so without this
    /// clause, closing that tab would delete the note outright. macOS never hit
    /// this: it embedded images in the note body itself, so an image-only note was
    /// never textually empty. Here the image is a row in another table.
    /// </remarks>
    public bool IsEmptyAndUntitled =>
        DisplayTitle == "Untitled"
        && string.IsNullOrWhiteSpace(BodyPlain)
        && !BodyHtml.Contains("<img", StringComparison.OrdinalIgnoreCase);
}
