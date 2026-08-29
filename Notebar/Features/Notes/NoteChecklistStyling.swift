import AppKit
import NotebarStore

/// The checked-item look for a checklist paragraph (spec §6.2b deliverable
/// 2): `text.secondary` plus a strikethrough over the item's own text,
/// applied as ordinary character attributes.
///
/// **Why restyling on load, not storing the colour.** Exactly
/// `NoteChipStyling`'s problem, solved the same way: `NoteRTF.attributedString(fromRTFD:)`/
/// `rtfdData(from:)` unconditionally strip `.foregroundColor` on every save
/// and load so ordinary text always tracks `NSTextView.textColor` across a
/// live theme switch (see that type's doc comment) — a checked item's
/// `.foregroundColor` would be stripped right along with it, so baking one
/// in at toggle time and never touching it again would make the item
/// silently lose its "checked" look the moment the note is reopened. The
/// fix is the same one `NoteChipStyling` uses for a chip's accent colour:
/// never treat the colour itself as the source of truth. Here the source of
/// truth is even simpler than a chip's — it's the checkbox glyph a
/// checklist marker already is (`☑` vs `□`, `NoteListMarkers`), which
/// *isn't* stripped (only `.foregroundColor` is), so which items are
/// checked is never lost. `restyled(_:)` below re-derives the look from
/// that glyph on every load, the same moment `NoteChipStyling.restyled` puts
/// a chip's colour back (`NoteEditorView.makeNSView`).
enum NoteChecklistStyling {
    /// Re-applies checked/unchecked styling to every checklist paragraph in
    /// `attributedString`, based purely on which glyph its marker already
    /// is. Called once, right after a note's body is decoded from its
    /// stored RTFD, alongside `NoteChipStyling.restyled`.
    static func restyled(_ attributedString: NSAttributedString) -> NSAttributedString {
        guard attributedString.length > 0 else { return attributedString }
        let mutable = NSMutableAttributedString(attributedString: attributedString)
        let nsString = mutable.string as NSString
        let length = nsString.length

        var location = 0
        while location < length {
            let paragraphRange = nsString.paragraphRange(for: NSRange(location: location, length: 0))
            if let style = mutable.attribute(.paragraphStyle, at: paragraphRange.location, effectiveRange: nil) as? NSParagraphStyle,
               style.textLists.first?.markerFormat == .check,
               let markerRange = NoteListMarkers.existingMarkerRange(in: nsString, paragraphRange: paragraphRange) {
                let glyph = nsString.substring(with: NSRange(location: markerRange.location, length: 1))
                let checked = glyph == NoteListMarkers.checklistCheckedGlyph

                let contentStart = markerRange.location + markerRange.length
                var contentEnd = paragraphRange.location + paragraphRange.length
                if contentEnd > contentStart, nsString.character(at: contentEnd - 1) == 10 /* "\n" */ {
                    contentEnd -= 1
                }
                apply(checked: checked, to: mutable, contentRange: NSRange(location: contentStart, length: max(contentEnd - contentStart, 0)))
            }
            location = paragraphRange.location + paragraphRange.length
        }
        return mutable
    }

    /// Applied directly at toggle time (`NoteListEditing.handleChecklistClick`)
    /// so an item's look updates the instant its checkbox is clicked, and
    /// again by `restyled(_:)` on every load — both call sites derive the
    /// exact same two attributes from the exact same "which glyph is this"
    /// question, never a different notion of what "checked" looks like.
    /// `contentRange` is the item's text only, never the marker itself — the
    /// checkbox glyph keeps its ordinary colour so it stays legible as a
    /// control rather than fading with the struck-through text.
    static func apply(checked: Bool, to textStorage: NSMutableAttributedString, contentRange: NSRange) {
        guard contentRange.length > 0 else { return }
        if checked {
            textStorage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: contentRange)
            textStorage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: contentRange)
        } else {
            textStorage.removeAttribute(.foregroundColor, range: contentRange)
            textStorage.removeAttribute(.strikethroughStyle, range: contentRange)
        }
    }
}
