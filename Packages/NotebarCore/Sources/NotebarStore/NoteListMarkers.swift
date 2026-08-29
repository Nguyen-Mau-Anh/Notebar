import AppKit
import Foundation

/// The text-level bookkeeping behind spec §6.2d's list behaviour.
///
/// `NSTextList` in a paragraph style is a hint TextKit reads for indentation
/// only — it draws no marker glyph itself. Without one, applying a list to
/// an empty line looks like nothing happened: the paragraph's indent has
/// nothing to indent. So the bullet/number has to exist as literal
/// characters at the start of the paragraph (`NSTextList.marker(forItemNumber:)`
/// plus a tab), and something has to keep those characters in sync with the
/// paragraph style and with each other as the document changes — that's what
/// this type does.
///
/// Lives in `NotebarStore`, not the app target, so the pure parts of it
/// (marker text for a given item number, finding an existing marker, diffing
/// a run's numbering) are testable directly against an `NSAttributedString`/
/// `NSMutableAttributedString`, without an `NSTextView`. The app target
/// (`NoteListEditing`, `Notebar/Features/Notes/`) owns everything that
/// genuinely needs a live text view — caret position, `typingAttributes`,
/// and the `shouldChangeTextIn`/Return-key glue.
public enum NoteListMarkers {
    /// The literal characters a list marker occupies at a paragraph's start:
    /// whatever glyph or number `list` draws for `itemNumber`, plus a tab so
    /// the paragraph's `firstLineHeadIndent`/`headIndent` actually separates
    /// marker from content. Bulleted lists (`markerFormat != .decimal`)
    /// ignore `itemNumber` — `NSTextList` itself returns the same glyph for
    /// every item — which is exactly why bulleted lists never need
    /// renumbering.
    ///
    /// `NSTextList.marker(forItemNumber:)` for `.decimal` returns the bare
    /// digits ("1", "2", ...) with no trailing punctuation — the format
    /// string behind the `.decimal` case is just `"{decimal}"`. A period is
    /// added here rather than by constructing the list with a custom format
    /// string like `"{decimal}."`, because `NoteTextStyling.activeStyles`
    /// and `orderedListRun` both identify an ordered list by comparing
    /// against the exact `.decimal` constant — a custom format string would
    /// stop matching it.
    public static func markerText(for itemNumber: Int, list: NSTextList) -> String {
        // A checklist item's marker doesn't come from `list.marker(forItemNumber:)`
        // at all — that API has no notion of checked/unchecked, only "which
        // glyph does this list style use." A checklist's `NSTextList` exists
        // solely to tag the paragraph as a checklist item (`.check`, chosen
        // because it's the semantically-named marker format, not because its
        // own glyph is used); the actual toggle state lives in the marker
        // text itself, and every *new* item — from `NoteListEditing.insertMarkers`
        // applying the style, or `handleReturn` starting the next item — is
        // unchecked (spec §6.2b: "Return on a checklist item creates the
        // next item unchecked").
        if list.markerFormat == .check {
            return checklistUncheckedGlyph + "\t"
        }
        let marker = list.marker(forItemNumber: itemNumber)
        let punctuated = list.markerFormat == .decimal ? marker + "." : marker
        return punctuated + "\t"
    }

    /// The unchecked checkbox glyph a fresh checklist item's marker is
    /// built from (`markerText(for:list:)` above).
    ///
    /// Deliberately not `☐` (U+2610 BALLOT BOX), the more obvious pick: it
    /// has no glyph in SF Pro at all — verified with
    /// `CTFontGetGlyphsForCharacters`, which reports glyph 0 (`.notdef`) for
    /// it on `.SFNS-Regular` — so it would render as nothing, exactly the
    /// failure mode that already hit `✕`/`⌄`/`▾`/`▼`/`▶` elsewhere in this
    /// project (fixed there by importing SVGs; here, by picking a different
    /// character instead). `□` (U+25A1 WHITE SQUARE) does have a glyph in
    /// SF Pro, confirmed the same way.
    public static let checklistUncheckedGlyph = "\u{25A1}"

    /// The checked checkbox glyph. `☑` (U+2611 BALLOT BOX WITH CHECK) was
    /// checked with the same `CTFontGetGlyphsForCharacters` probe and does
    /// have a glyph in SF Pro.
    public static let checklistCheckedGlyph = "\u{2611}"

    /// What a click on `existingGlyph` should turn it into, or `nil` if
    /// `existingGlyph` isn't a checklist glyph at all — a plain character
    /// lookup, deliberately kept separate from `toggleChecklistGlyph(at:in:)`
    /// below so the state-flip rule itself (unchecked ↔ checked, nothing
    /// else) is directly testable without an `NSMutableAttributedString`.
    public static func toggledChecklistGlyph(_ existingGlyph: String) -> String? {
        switch existingGlyph {
        case checklistUncheckedGlyph: checklistCheckedGlyph
        case checklistCheckedGlyph: checklistUncheckedGlyph
        default: nil
        }
    }

    /// Flips the checkbox glyph at `location` in place — the one character
    /// there, and nothing else. `location` must be exactly where an
    /// existing checkbox glyph sits (a checklist marker's first character);
    /// anywhere else, or a character that isn't a checklist glyph at all, is
    /// a no-op that returns `false` and leaves `text` untouched.
    ///
    /// Deliberately a single-character replacement rather than anything
    /// range-based over the paragraph: this is what guarantees toggling one
    /// item can never reach into a neighbouring paragraph's own marker
    /// (spec deliverable 2's "toggling an item changes only its own
    /// marker"). Finding *which* location a click landed on is
    /// `NSTextView`-geometry work the app target's
    /// `NoteListEditing.handleChecklistClick` owns; this only performs the
    /// mutation once that location is already known.
    @discardableResult
    public static func toggleChecklistGlyph(at location: Int, in text: NSMutableAttributedString) -> Bool {
        let nsString = text.string as NSString
        guard location >= 0, location < nsString.length else { return false }
        let existingGlyph = nsString.substring(with: NSRange(location: location, length: 1))
        guard let newGlyph = toggledChecklistGlyph(existingGlyph) else { return false }
        let attributes = text.attributes(at: location, effectiveRange: nil)
        text.replaceCharacters(in: NSRange(location: location, length: 1), with: NSAttributedString(string: newGlyph, attributes: attributes))
        return true
    }

    /// Whether a paragraph carrying `style` is a list item at all.
    public static func isListParagraph(_ style: NSParagraphStyle?) -> Bool {
        !(style?.textLists.isEmpty ?? true)
    }

    /// The range of a marker already sitting at the start of the paragraph
    /// spanning `paragraphRange`, if any.
    ///
    /// A list paragraph's marker is always immediately followed by a tab
    /// (see `markerText`), so the first tab found within the paragraph — if
    /// there is one — marks the end of an existing marker. A list paragraph
    /// with no tab yet has no marker: exactly the instant between applying
    /// the paragraph style and inserting the marker text.
    ///
    /// This is a textual heuristic, not a tagged range — a custom attribute
    /// would be the more precise way to mark "this run is a marker", but
    /// custom attribute keys don't survive the RTFD round trip `NoteRTF`
    /// persists notes through, so a marker has to be recognizable from its
    /// text alone. A list item whose own content happened to start with a
    /// literal tab would be misidentified; nothing in this editor lets a
    /// user type one today.
    public static func existingMarkerRange(in text: NSString, paragraphRange: NSRange) -> NSRange? {
        guard paragraphRange.length > 0 else { return nil }
        let tabRange = text.rangeOfCharacter(from: CharacterSet(charactersIn: "\t"), options: [], range: paragraphRange)
        guard tabRange.location != NSNotFound else { return nil }
        return NSRange(location: paragraphRange.location, length: tabRange.location + tabRange.length - paragraphRange.location)
    }

    /// Diffs `items` — the current marker text of each paragraph in one
    /// contiguous ordered-list run, in document order — against what
    /// `list.marker(forItemNumber:)` actually produces for positions
    /// `1...items.count`. Returns only the entries that need to change,
    /// keyed by index into `items`, so a caller can leave an already-correct
    /// run untouched rather than rewriting every marker on every edit.
    public static func renumbering(for items: [String], list: NSTextList) -> [Int: String] {
        var changes: [Int: String] = [:]
        for (index, current) in items.enumerated() {
            let expected = markerText(for: index + 1, list: list)
            if current != expected {
                changes[index] = expected
            }
        }
        return changes
    }

    /// The paragraph ranges of the maximal contiguous run of *ordered*
    /// list paragraphs containing `location` — every paragraph immediately
    /// above and below that also carries a `.decimal` `NSTextList`, stopping
    /// at the first paragraph that doesn't (or at either end of the
    /// document). `nil` if the paragraph at `location` isn't itself part of
    /// an ordered list.
    ///
    /// Bulleted lists never appear here: their marker never depends on
    /// position, so there's nothing for a "run" to renumber (spec §6.2d).
    public static func orderedListRun(containing location: Int, in text: NSAttributedString) -> [NSRange]? {
        let nsString = text.string as NSString
        let length = nsString.length
        guard length > 0 else { return nil }
        let clamped = min(max(location, 0), length - 1)

        func isOrdered(at loc: Int) -> Bool {
            let style = text.attribute(.paragraphStyle, at: loc, effectiveRange: nil) as? NSParagraphStyle
            return style?.textLists.first?.markerFormat == .decimal
        }

        guard isOrdered(at: clamped) else { return nil }

        var ranges = [nsString.paragraphRange(for: NSRange(location: clamped, length: 0))]

        while ranges[0].location > 0, isOrdered(at: ranges[0].location - 1) {
            let previous = nsString.paragraphRange(for: NSRange(location: ranges[0].location - 1, length: 0))
            ranges.insert(previous, at: 0)
        }

        while let last = ranges.last, last.location + last.length < length, isOrdered(at: last.location + last.length) {
            let next = nsString.paragraphRange(for: NSRange(location: last.location + last.length, length: 0))
            ranges.append(next)
        }

        return ranges
    }

    /// Rewrites `run`'s markers in place so item numbers read 1, 2, 3, ...
    /// Returns `true` if anything actually changed, so a caller can skip
    /// posting a "text changed" notification for a run that was already
    /// correctly numbered.
    ///
    /// `run`'s ranges must be in ascending document order (as
    /// `orderedListRun` produces them). Mutations are applied from the last
    /// paragraph to the first: replacing one marker can change its length
    /// (e.g. "9." → "10."), which would invalidate every range after it —
    /// working backward means every range still to be processed is always
    /// at a lower, still-valid offset.
    @discardableResult
    public static func renumber(run: [NSRange], list: NSTextList, in text: NSMutableAttributedString) -> Bool {
        let nsString = text.string as NSString
        let currentMarkers = run.map { range -> String in
            guard let markerRange = existingMarkerRange(in: nsString, paragraphRange: range) else { return "" }
            return nsString.substring(with: markerRange)
        }
        let changes = renumbering(for: currentMarkers, list: list)
        guard !changes.isEmpty else { return false }

        for index in changes.keys.sorted(by: >) {
            guard let replacement = changes[index] else { continue }
            let paragraphRange = run[index]
            let freshString = text.string as NSString
            if let existing = existingMarkerRange(in: freshString, paragraphRange: paragraphRange) {
                let attributes = text.attributes(at: existing.location, effectiveRange: nil)
                text.replaceCharacters(in: existing, with: NSAttributedString(string: replacement, attributes: attributes))
            } else if paragraphRange.location < text.length {
                let attributes = text.attributes(at: paragraphRange.location, effectiveRange: nil)
                text.insert(NSAttributedString(string: replacement, attributes: attributes), at: paragraphRange.location)
            }
        }
        return true
    }

    /// The visible text of `attributedString` with every list marker
    /// removed — what `NoteRTF.plainText(from:)` actually stores as
    /// `body_plain`. A marker is real text so TextKit has something to
    /// render, but it isn't something the user wrote: the same
    /// bookkeeping-vs-content line `NoteRTF` already draws for an embedded
    /// image, which contributes no text to `body_plain` either. Without
    /// this, a numbered list's "1.", "2.", ... would sit in `note_fts`
    /// alongside the user's actual words.
    public static func strippingMarkers(from attributedString: NSAttributedString) -> String {
        let length = attributedString.length
        guard length > 0 else { return "" }
        let nsString = attributedString.string as NSString

        var result = ""
        var location = 0
        repeat {
            let paragraphRange = nsString.paragraphRange(for: NSRange(location: location, length: 0))
            let style = attributedString.attribute(.paragraphStyle, at: paragraphRange.location, effectiveRange: nil) as? NSParagraphStyle
            if isListParagraph(style), let markerRange = existingMarkerRange(in: nsString, paragraphRange: paragraphRange) {
                let beforeMarker = NSRange(location: paragraphRange.location, length: markerRange.location - paragraphRange.location)
                if beforeMarker.length > 0 { result += nsString.substring(with: beforeMarker) }
                let afterMarkerStart = markerRange.location + markerRange.length
                let afterMarkerLength = paragraphRange.location + paragraphRange.length - afterMarkerStart
                if afterMarkerLength > 0 { result += nsString.substring(with: NSRange(location: afterMarkerStart, length: afterMarkerLength)) }
            } else {
                result += nsString.substring(with: paragraphRange)
            }
            location = paragraphRange.location + paragraphRange.length
        } while location < length

        return result
    }
}
