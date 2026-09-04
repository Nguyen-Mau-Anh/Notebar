namespace Notebar.Core.Models;

/// <summary>A single edge between two notes or tasks. One generic table covers
/// note→task, task→note, note→note, and task→task, so Link carries no notion of
/// "the note side" — only SrcType/DstType, mirroring the columns exactly.</summary>
public sealed record Link(
    string Id,
    LinkEntityType SrcType,
    string SrcId,
    LinkEntityType DstType,
    string DstId,
    string Kind,
    DateTimeOffset CreatedAt)
{
    /// <summary>The only kind any link is created with today. A string constant
    /// rather than an enum: kind is meant to grow (a future "blocks" or
    /// "duplicates" relation) without widening a closed type every time.</summary>
    public const string ReferencesKind = "references";

    public static Link New(LinkTarget source, LinkTarget destination) =>
        new(Guid.NewGuid().ToString(), source.Type, source.Id,
            destination.Type, destination.Id, ReferencesKind, DateTimeOffset.UtcNow);

    public LinkTarget Source => new(SrcType, SrcId);
    public LinkTarget Destination => new(DstType, DstId);
}
