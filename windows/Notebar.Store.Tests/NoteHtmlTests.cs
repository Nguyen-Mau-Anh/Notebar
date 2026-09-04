using Notebar.Store;
using Xunit;

namespace Notebar.Store.Tests;

public class NoteHtmlTests
{
    [Fact]
    public void StripsTags() =>
        Assert.Equal("hello world", NoteHtml.ToPlainText("<p><b>hello</b> world</p>"));

    [Fact]
    public void BlockElementsBecomeLineBreaks() =>
        Assert.Equal("one\ntwo", NoteHtml.ToPlainText("<p>one</p><p>two</p>"));

    [Fact]
    public void BrBecomesALineBreak() =>
        Assert.Equal("one\ntwo", NoteHtml.ToPlainText("one<br>two"));

    [Fact]
    public void DecodesEntities() =>
        Assert.Equal("a & b < c", NoteHtml.ToPlainText("a &amp; b &lt; c"));

    /// A checkbox is editor bookkeeping, not text the user wrote. Indexing it
    /// would make every checklist note match a search for the glyph.
    [Fact]
    public void CheckboxInputsContributeNothing() =>
        Assert.Equal("buy milk",
            NoteHtml.ToPlainText("<ul><li><input type=\"checkbox\">buy milk</li></ul>"));

    /// Likewise list markers: the browser draws them, they are not in the markup,
    /// and nothing should invent them here either.
    [Fact]
    public void ListItemsAreOneLineEachWithNoMarkers() =>
        Assert.Equal("first\nsecond",
            NoteHtml.ToPlainText("<ul><li>first</li><li>second</li></ul>"));

    /// An image contributes no text, but must not swallow the text around it.
    [Fact]
    public void ImagesContributeNothing() =>
        Assert.Equal("before after",
            NoteHtml.ToPlainText("before <img src=\"https://notebar.local/asset/x\"> after"));

    /// A link chip's visible label is real text the user can search for. Its href
    /// is not.
    [Fact]
    public void ChipLabelsAreIndexedButNotTheirUrls()
    {
        string plain = NoteHtml.ToPlainText(
            "see <a href=\"notebar://note/abc-123\">Groceries</a>");
        Assert.Contains("Groceries", plain);
        Assert.DoesNotContain("notebar://", plain);
        Assert.DoesNotContain("abc-123", plain);
    }

    /// An untouched editor produces markup but no text, and Note.IsEmptyAndUntitled
    /// depends on that becoming the empty string.
    [Fact]
    public void AnEmptyDocumentIsTheEmptyString() =>
        Assert.Equal("", NoteHtml.ToPlainText("<p><br></p>"));

    [Fact]
    public void ScriptAndStyleContentIsNotText() =>
        Assert.Equal("visible",
            NoteHtml.ToPlainText("<style>p{color:red}</style>visible<script>alert(1)</script>"));
}
