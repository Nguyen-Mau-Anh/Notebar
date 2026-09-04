namespace Notebar.App.Features.Notes;

/// <summary>A per-render projection of an open note for NoteTabStrip's item template.</summary>
/// <remarks>
/// Note itself carries no notion of "is this the active tab" -- that is strip state, not
/// note state -- so NoteTabStrip builds one of these per open note, freshly, every time it
/// redraws. IsInactive exists only because x:Bind's implicit bool-to-Visibility conversion
/// needs a plain property to bind against; there is no clean way to negate an x:Bind
/// expression inline in the markup.
/// </remarks>
internal sealed record NoteTabItem(string Id, string DisplayTitle, bool IsActive)
{
    public bool IsInactive => !IsActive;
}
