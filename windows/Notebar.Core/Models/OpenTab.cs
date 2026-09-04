namespace Notebar.Core.Models;

/// <summary>A persisted entry in the open-tab strip. Open tabs survive a restart;
/// this is what makes that possible.</summary>
public sealed record OpenTab(string Id, string Kind, string RefId, double SortOrder, bool IsActive)
{
    /// <summary>A string constant rather than an enum: kinds are schema data other
    /// tabs add to later, not a fixed set the type system should close over.</summary>
    public const string NoteKind = "note";
}
