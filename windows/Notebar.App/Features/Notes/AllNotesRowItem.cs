namespace Notebar.App.Features.Notes;

/// <summary>A per-render row for AllNotesMenu's list: NoteSummary plus the two facts the
/// menu adds -- a relative-time string and whether the note already has an open tab.
/// NoteSummary itself is deliberately body-less (see its own remarks); this stays that way
/// too.</summary>
internal sealed record AllNotesRowItem(string Id, string DisplayTitle, string RelativeTime, bool IsOpen);
