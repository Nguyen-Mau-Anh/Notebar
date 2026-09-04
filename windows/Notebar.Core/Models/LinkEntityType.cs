namespace Notebar.Core.Models;

/// <summary>The two kinds of thing a Link can point at.</summary>
/// <remarks>
/// A real enum, unlike OpenTab.Kind or BoardColumn.Kind — those are deliberately
/// open-ended schema data a future case can extend; a link's two endpoints are
/// exactly notes and tasks for the whole life of this table, so closing the type
/// over them catches a typo'd "nott" at compile time instead of as a silent
/// zero-row query at runtime.
/// </remarks>
public enum LinkEntityType { Note, Task }

public static class LinkEntityTypeExtensions
{
    public static string ToStorageString(this LinkEntityType type) =>
        type == LinkEntityType.Note ? "note" : "task";

    public static LinkEntityType? Parse(string? raw) => raw switch
    {
        "note" => LinkEntityType.Note,
        "task" => LinkEntityType.Task,
        _ => null,
    };
}
