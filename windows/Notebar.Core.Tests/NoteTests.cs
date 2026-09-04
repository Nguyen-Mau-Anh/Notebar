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
}
