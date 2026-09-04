namespace Notebar.Core.Models;

/// <summary>One endpoint of a Link — an entity type plus its id — used instead of
/// two loose parameters, so a caller cannot transpose a type and an id that
/// happen to both be strings.</summary>
/// <remarks>
/// A record struct, so it is usable as a HashSet element: the tombstone check
/// collects every note and task id that still exists into a set once per note
/// load, making "did this chip's target survive" a set lookup rather than a query
/// per chip.
/// </remarks>
public readonly record struct LinkTarget(LinkEntityType Type, string Id);
