namespace Notebar.Core.Models;

/// <summary>A tasks board. v1 seeds exactly one, but the schema does not assume
/// a single board.</summary>
public sealed record Board(string Id, string Name, double SortOrder);
