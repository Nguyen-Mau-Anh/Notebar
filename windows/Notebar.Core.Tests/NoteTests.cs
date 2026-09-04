using Notebar.Core.Models;
using Xunit;

namespace Notebar.Core.Tests;

public class NoteTests
{
    private static Note Fresh() => Note.New(sortOrder: 0);

    [Fact]
    public void FreshNoteIsEmptyAndUntitled() =>
        Assert.True(Fresh().IsEmptyAndUntitled);

    [Fact]
    public void NoteWithBodyIsNotEmptyAndUntitled() =>
        Assert.False((Fresh() with { BodyPlain = "something" }).IsEmptyAndUntitled);

    [Fact]
    public void NoteWithTitleIsNotEmptyAndUntitled() =>
        Assert.False((Fresh() with { Title = "Groceries" }).IsEmptyAndUntitled);

    [Fact]
    public void WhitespaceOnlyBodyIsStillEmpty() =>
        Assert.True((Fresh() with { BodyPlain = "  \n\t " }).IsEmptyAndUntitled);

    /// The macOS version of this test asserted that a body serialising to a
    /// non-trivial RTF header is still "empty". The HTML equivalent: an editor
    /// that has been focused but not typed in produces markup, and that markup
    /// must not count as content.
    [Fact]
    public void HtmlBodyWithNoVisibleTextIsStillEmpty() =>
        Assert.True((Fresh() with { BodyHtml = "<p><br></p>", BodyPlain = "" }).IsEmptyAndUntitled);

    /// A note whose only content is a pasted image is NOT empty — closing its tab
    /// must not delete it. BodyPlain is "" for an img, which is what made this the
    /// one kind of real content that read as disposable.
    [Fact]
    public void ANoteContainingOnlyAnImageIsNotEmpty()
    {
        var note = Fresh() with
        {
            BodyHtml = "<p><img src=\"https://notebar.local/asset/abc\"></p>",
            BodyPlain = "",
        };
        Assert.False(note.IsEmptyAndUntitled);
    }

    /// The rename UI refuses to commit a blank title, so this branch is
    /// defensive — but the tab strip renders it, so it must not quietly become
    /// an empty tab label.
    [Fact]
    public void AnEmptyTitleDisplaysAsUntitled()
    {
        Assert.Equal("Untitled", (Fresh() with { Title = "" }).DisplayTitle);
        Assert.Equal("Groceries", (Fresh() with { Title = "Groceries" }).DisplayTitle);
    }

    /// NoteSummary is what the all-notes menu renders while Note is what the tab
    /// strip renders. If these two ever disagree, the same note shows one name in
    /// the menu and another on its tab.
    [Fact]
    public void NoteSummaryDisplayTitleMirrorsNote()
    {
        foreach (var title in new[] { "", "Untitled", "Groceries" })
        {
            var note = Fresh() with { Title = title };
            var summary = new NoteSummary(note.Id, title, note.UpdatedAt);
            Assert.Equal(note.DisplayTitle, summary.DisplayTitle);
        }
    }
}
