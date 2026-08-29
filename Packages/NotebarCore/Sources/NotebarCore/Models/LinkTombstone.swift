import Foundation

/// The pure "is this chip's target gone" predicate behind spec §6.4
/// deliverable 3's tombstones — split out from the AppKit styling that
/// actually paints a tombstone (`NoteChipStyling` in the app target, which
/// this package must never import — spec section 3, rule 1) so the decision
/// itself is unit-testable here, the same split `NoteListMarkers`/
/// `NoteListEditing` already draw between "the pure logic" and "the
/// `NSTextView` glue."
///
/// **Why this can't be answered from the `link` table.** `LinkSchema`'s
/// `AFTER DELETE` triggers cascade: deleting a note or task also deletes
/// every `link` row that touches it, on either end. So by the time a chip
/// needs restyling, the row behind it is already gone too — a tombstone
/// can't be detected by asking "does a link row still point here," only by
/// asking "does the target itself still exist." Callers answer that once,
/// not per chip — see `PanelViewModel.existingLinkTargets()`.
public enum LinkTombstone {
    /// `nil` when `url` isn't a chip this app ever wrote at all (a foreign
    /// scheme, or a malformed `notebar://` URL) — mirrors `LinkURL.parse`'s
    /// own `nil` case, so a caller can tell "not a chip" apart from "a chip
    /// whose target is gone." `true` when it is a chip and `existingTargets`
    /// (every note/task id known to still exist, batched ahead of time) does
    /// not contain its target.
    public static func isTombstone(url: URL, existingTargets: Set<LinkTarget>) -> Bool? {
        guard let target = LinkURL.parse(url) else { return nil }
        return !existingTargets.contains(target)
    }
}
