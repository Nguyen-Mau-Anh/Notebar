using Notebar.Core.Models;
using Xunit;

namespace Notebar.Core.Tests;

public class LinkUrlTests
{
    [Fact]
    public void RoundTripsANote()
    {
        var target = new LinkTarget(LinkEntityType.Note, "abc-123");
        Assert.Equal("notebar://note/abc-123", LinkUrl.Build(target));
        Assert.Equal(target, LinkUrl.Parse(LinkUrl.Build(target)));
    }

    [Fact]
    public void RoundTripsATask()
    {
        var target = new LinkTarget(LinkEntityType.Task, "def-456");
        Assert.Equal("notebar://task/def-456", LinkUrl.Build(target));
        Assert.Equal(target, LinkUrl.Parse(LinkUrl.Build(target)));
    }

    [Theory]
    [InlineData("https://example.com/note/abc")]   // foreign scheme
    [InlineData("notebar://widget/abc")]           // unknown entity type
    [InlineData("notebar://note/")]                // empty id
    [InlineData("notebar://note")]                 // no separator
    [InlineData("notebar://")]                     // nothing at all
    [InlineData("")]
    public void RejectsAnythingItDidNotBuild(string url) =>
        Assert.Null(LinkUrl.Parse(url));
}
