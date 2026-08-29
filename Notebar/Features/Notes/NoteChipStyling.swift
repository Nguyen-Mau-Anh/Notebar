import AppKit
import NotebarCore

/// The chip look for a `.link` run pointing at a `notebar://` URL (spec
/// §6.4): accent foreground plus a faint accent-tinted background, applied
/// as ordinary character attributes alongside `.link`.
///
/// **Why restyling on load, not exempting the run from the colour strip.**
/// `NoteRTF.attributedString(fromRTFD:)`/`rtfdData(from:)` unconditionally
/// strip `.foregroundColor` so ordinary text always tracks
/// `NSTextView.textColor` across a live theme switch — see that type's doc
/// comment. Baking any colour into a saved run, chip or not, would freeze it
/// at whatever appearance was active on save; the fix used there for
/// ordinary text (never store a colour, always resolve from `textColor`)
/// doesn't apply to a chip, which needs its own colour independent of the
/// surrounding text. Re-deriving that colour from the `.link` attribute on
/// every load sidesteps the conflict instead of special-casing `NoteRTF`'s
/// strip: `.link`, unlike `.foregroundColor`, is never stripped, so which
/// runs are chips is never lost, and `NSColor.controlAccentColor` — a
/// dynamic system colour, the same kind `.labelColor` is — resolves per
/// appearance at draw time exactly like the rest of the text does, with
/// nothing serialized ever going stale. `NoteTextView.viewDidChangeEffectiveAppearance`
/// already forces `needsDisplay = true` on every appearance change, which is
/// what makes an already-drawn chip repaint in the new appearance's accent
/// colour without this needing its own observer.
enum NoteChipStyling {
    /// Re-applies chip styling to every `.link` run in `attributedString`
    /// that points at a `notebar://` URL. Called once, right after a note's
    /// body is decoded from its stored RTFD (`NoteEditorView.makeNSView`) —
    /// `.link` survived the round trip, but `.foregroundColor` did not, so
    /// every chip needs its colour put back before the text view ever draws
    /// it.
    ///
    /// `existingTargets` (spec §6.4 deliverable 3's tombstones) is the set
    /// of every note/task id still known to exist, computed once by
    /// `PanelViewModel.existingLinkTargets()` — one query, not one per chip
    /// — and handed to `LinkTombstone.isTombstone(url:existingTargets:)` for
    /// each run found. A run whose target survived gets the ordinary chip
    /// look; one whose target is gone gets `applyTombstone` instead.
    ///
    /// Tombstone ranges are collected during the enumeration and restyled in
    /// a second pass, after `enumerateAttribute(.link:...)` has finished —
    /// `applyTombstone` removes `.link` itself, and mutating the very
    /// attribute an enumeration is walking is undefined while it's still in
    /// progress.
    static func restyled(_ attributedString: NSAttributedString, existingTargets: Set<LinkTarget>) -> NSAttributedString {
        guard attributedString.length > 0 else { return attributedString }
        let mutable = NSMutableAttributedString(attributedString: attributedString)
        var tombstoneRanges: [NSRange] = []
        mutable.enumerateAttribute(.link, in: NSRange(location: 0, length: mutable.length)) { value, range, _ in
            guard let url = value as? URL, let isTombstone = LinkTombstone.isTombstone(url: url, existingTargets: existingTargets) else { return }
            if isTombstone {
                tombstoneRanges.append(range)
            } else {
                apply(to: mutable, range: range)
            }
        }
        for range in tombstoneRanges {
            applyTombstone(to: mutable, range: range)
        }
        return mutable
    }

    /// Applied directly to a freshly built chip run at insertion time
    /// (`NoteEditorView.Coordinator.insertChip`), so a chip looks identical
    /// the instant it's inserted and after every subsequent reload —
    /// `restyled(_:)` above reapplies the exact same two attributes, never a
    /// different derivation of "what a chip looks like."
    static func apply(to textStorage: NSMutableAttributedString, range: NSRange) {
        textStorage.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: range)
        textStorage.addAttribute(.backgroundColor, value: NSColor.controlAccentColor.withAlphaComponent(0.14), range: range)
    }

    /// The tombstone look (spec §6.4 deliverable 3): the chip's text
    /// survives untouched — this only ever changes attributes, never
    /// `textStorage.replaceCharacters` — struck through, in
    /// `NSColor.tertiaryLabelColor` (a dynamic system colour, same kind
    /// `.labelColor`/`.controlAccentColor` already are, so it also tracks a
    /// live theme switch), with the accent background and, crucially, the
    /// `.link` attribute itself removed. Removing `.link` is what makes the
    /// tombstone non-interactive: `NSTextView` only routes a click to
    /// `textView(_:clickedOnLink:at:)` for a run that still carries one, so
    /// a stripped-off `.link` needs no separate "ignore clicks on a
    /// tombstone" check anywhere else.
    static func applyTombstone(to textStorage: NSMutableAttributedString, range: NSRange) {
        textStorage.removeAttribute(.link, range: range)
        textStorage.removeAttribute(.backgroundColor, range: range)
        textStorage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: range)
        textStorage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
    }
}
