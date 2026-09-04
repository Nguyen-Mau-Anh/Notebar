using Notebar.Core.Models;
using Xunit;

namespace Notebar.Core.Tests;

public class LinkTombstoneTests
{
    private static readonly IReadOnlySet<LinkTarget> Existing = new HashSet<LinkTarget>
    {
        new(LinkEntityType.Note, "note-1"),
        new(LinkEntityType.Task, "task-1"),
    };

    [Fact]
    public void TargetExists() =>
        Assert.False(LinkTombstone.IsTombstone("notebar://note/note-1", Existing));

    [Fact]
    public void TargetMissing() =>
        Assert.True(LinkTombstone.IsTombstone("notebar://note/note-99", Existing));

    /// A note and a task can share an id string. The type is part of identity.
    [Fact]
    public void TypeMatters() =>
        Assert.True(LinkTombstone.IsTombstone("notebar://task/note-1", Existing));

    /// Null, not true: a caller must be able to tell "not a chip" apart from
    /// "a chip whose target is gone", because only the second gets restyled.
    [Fact]
    public void NotAChip() =>
        Assert.Null(LinkTombstone.IsTombstone("https://example.com", Existing));
}
