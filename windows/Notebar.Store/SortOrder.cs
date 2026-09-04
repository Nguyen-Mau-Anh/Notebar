namespace Notebar.Store;

/// <summary>Fractional ordering: a reorder is one row update rather than a
/// renumbering pass over the whole list.</summary>
/// <remarks>
/// The cost is that repeatedly inserting between the same two neighbours halves
/// the gap each time, and doubles run out of room after about 50 such inserts.
/// SortOrderTests pins that depth. Nothing in this app comes close — a user
/// would have to drag the same card into the same slot fifty times without ever
/// dragging anything else — but if a future feature does, the fix is a
/// renumbering pass, not a bigger number type.
/// </remarks>
public static class SortOrder
{
    /// <summary>A value strictly between the two neighbours' orders. Null means
    /// "that end of the list".</summary>
    public static double Between(double? before, double? after) => (before, after) switch
    {
        (null, null) => 0.0,
        (null, { } a) => a - 1.0,
        ({ } b, null) => b + 1.0,
        ({ } b, { } a) => (b + a) / 2.0,
    };
}
