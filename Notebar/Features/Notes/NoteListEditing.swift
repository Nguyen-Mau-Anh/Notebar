import AppKit
import NotebarStore

/// The `NSTextView`-facing half of spec §6.2d's list bookkeeping — the
/// counterpart to `NotebarStore.NoteListMarkers`, which owns everything
/// about marker text and renumbering that's testable without a live text
/// view. This type owns what genuinely needs one: reading the caret and
/// selection, updating `typingAttributes`, and the Return-key idiom for
/// starting or escaping a list.
///
/// Called from two places: `NoteTextStyling.toggleList` (applying or
/// removing the style — the "click the bar button" path) and
/// `NoteEditorView.Coordinator` (the Return key and the post-edit
/// renumbering safety net).
enum NoteListEditing {
    // MARK: - Applying / removing the list style

    /// Inserts a marker at the start of every paragraph in the current
    /// selection's paragraph range that doesn't already have one —
    /// including an entirely empty document, which is exactly the case that
    /// made lists look broken (spec §6.2d): `NoteTextStyling.toggleList`
    /// already sets `typingAttributes`'s paragraph style for that case, but
    /// there's no character yet for a paragraph-style attribute to attach
    /// to, so nothing renders without a real character inserted here.
    ///
    /// Must run *after* the new `NSTextList` is already in the paragraph
    /// style (`NoteTextStyling.applyParagraphStyle` has already run) — the
    /// marker text is read from that list.
    static func insertMarkers(in textView: NSTextView, ordered: Bool) {
        guard let textStorage = textView.textStorage else { return }

        let blockRange: NSRange = textStorage.length == 0
            ? NSRange(location: 0, length: 0)
            : (textStorage.string as NSString).paragraphRange(for: textView.selectedRange())
        let ranges = paragraphRanges(in: blockRange, textStorage: textStorage)

        let originalSelection = textView.selectedRange()
        var caretShift = 0

        textStorage.beginEditing()
        for paragraphRange in ranges.reversed() {
            guard let list = paragraphStyle(at: paragraphRange.location, in: textView)?.textLists.first else { continue }
            let currentString = textStorage.string as NSString
            guard NoteListMarkers.existingMarkerRange(in: currentString, paragraphRange: paragraphRange) == nil else { continue }

            let marker = NoteListMarkers.markerText(for: 1, list: list)
            let markerAttributes = attributes(at: paragraphRange.location, in: textView)
            textStorage.replaceCharacters(in: NSRange(location: paragraphRange.location, length: 0), with: NSAttributedString(string: marker, attributes: markerAttributes))

            if paragraphRange.location <= originalSelection.location {
                caretShift += (marker as NSString).length
            }
        }
        textStorage.endEditing()

        textView.setSelectedRange(NSRange(location: originalSelection.location + caretShift, length: max(originalSelection.length, 0)))
        textView.didChangeText()

        if ordered {
            renumberRun(near: textView.selectedRange().location, in: textView)
        }
    }

    /// Strips whatever marker each paragraph in the current selection's
    /// paragraph range carries. Must run *before* the list's `NSTextList` is
    /// cleared from the paragraph style — this reads `isListParagraph` off
    /// the still-current style to know which paragraphs have a marker to
    /// remove at all.
    static func stripMarkers(in textView: NSTextView) {
        guard let textStorage = textView.textStorage, textStorage.length > 0 else { return }

        let blockRange = (textStorage.string as NSString).paragraphRange(for: textView.selectedRange())
        let ranges = paragraphRanges(in: blockRange, textStorage: textStorage)

        let originalSelection = textView.selectedRange()
        var caretShift = 0

        textStorage.beginEditing()
        for paragraphRange in ranges.reversed() {
            guard let style = paragraphStyle(at: paragraphRange.location, in: textView), NoteListMarkers.isListParagraph(style) else { continue }
            let currentString = textStorage.string as NSString
            guard let markerRange = NoteListMarkers.existingMarkerRange(in: currentString, paragraphRange: paragraphRange) else { continue }
            textStorage.deleteCharacters(in: markerRange)

            if markerRange.location < originalSelection.location {
                caretShift -= min(markerRange.length, originalSelection.location - markerRange.location)
            }
        }
        textStorage.endEditing()

        let newLocation = max(originalSelection.location + caretShift, 0)
        textView.setSelectedRange(NSRange(location: newLocation, length: max(originalSelection.length, 0)))
        textView.didChangeText()

        // Removing only part of an ordered run splits it in two — the
        // paragraphs after this block need to restart their numbering at 1
        // rather than continuing where the removed block left off.
        renumberRun(near: blockRange.location + blockRange.length, in: textView)
    }

    // MARK: - Return key

    /// Intercepts Return inside a list item (spec §6.2d): ending an empty
    /// item exits the list instead of adding another blank one — the
    /// standard editor idiom for getting out, and without it a list is a
    /// trap — while continuing a populated item starts the next one with
    /// its own marker in the same edit, so there's never a moment with a
    /// bare, marker-less list paragraph on screen.
    ///
    /// Returns `true` if this fully handled `range`; the caller
    /// (`NoteEditorView.Coordinator`) must then reject the default text
    /// change. Returns `false` to let Return behave normally — the
    /// paragraph at `range` isn't a list item at all.
    static func handleReturn(in textView: NSTextView, range: NSRange) -> Bool {
        guard let textStorage = textView.textStorage, textStorage.length > 0, range.location <= textStorage.length else { return false }

        let nsString = textStorage.string as NSString
        let paragraphRange = nsString.paragraphRange(for: NSRange(location: min(range.location, textStorage.length), length: 0))
        guard let style = paragraphStyle(at: paragraphRange.location, in: textView),
              NoteListMarkers.isListParagraph(style),
              let list = style.textLists.first
        else { return false }

        let markerRange = NoteListMarkers.existingMarkerRange(in: nsString, paragraphRange: paragraphRange)
        let contentStart = (markerRange?.location ?? paragraphRange.location) + (markerRange?.length ?? 0)
        var contentEnd = paragraphRange.location + paragraphRange.length
        if contentEnd > contentStart, nsString.character(at: contentEnd - 1) == 10 /* "\n" */ {
            contentEnd -= 1
        }
        let isEmptyItem = contentEnd <= contentStart

        textStorage.beginEditing()
        if isEmptyItem {
            if let markerRange {
                textStorage.deleteCharacters(in: markerRange)
            }
            let plainStyle = (style.mutableCopy() as? NSMutableParagraphStyle) ?? NoteFont.bodyParagraphStyle
            plainStyle.textLists = []
            plainStyle.headIndent = 0
            plainStyle.firstLineHeadIndent = 0
            let remainingLength = paragraphRange.length - (markerRange?.length ?? 0)
            if remainingLength > 0 {
                textStorage.addAttribute(.paragraphStyle, value: plainStyle, range: NSRange(location: paragraphRange.location, length: remainingLength))
            }
            textView.typingAttributes[.paragraphStyle] = plainStyle
            textStorage.endEditing()

            textView.setSelectedRange(NSRange(location: paragraphRange.location, length: 0))
            textView.didChangeText()
            renumberRun(near: paragraphRange.location + remainingLength, in: textView)
        } else {
            let marker = NoteListMarkers.markerText(for: 1, list: list)
            let insertion = "\n" + marker
            let insertionAttributes = attributes(at: min(range.location, textStorage.length - 1), in: textView)
            textStorage.replaceCharacters(in: range, with: NSAttributedString(string: insertion, attributes: insertionAttributes))
            // The inserted newline terminates the item being split (still a
            // list paragraph) and the marker after it starts the next one —
            // both need the same list paragraph style regardless of what
            // font/color the caret happened to be sitting in.
            textStorage.addAttribute(.paragraphStyle, value: style, range: NSRange(location: range.location, length: (insertion as NSString).length))
            textStorage.endEditing()

            textView.typingAttributes[.paragraphStyle] = style
            textView.setSelectedRange(NSRange(location: range.location + (insertion as NSString).length, length: 0))
            textView.didChangeText()
            if list.markerFormat == .decimal {
                renumberRun(near: textView.selectedRange().location, in: textView)
            }
        }
        return true
    }

    // MARK: - Renumbering

    /// The general-purpose safety net: if the paragraph at `location` is
    /// part of an ordered-list run, renumber the whole run. Called after
    /// every edit that could plausibly have added, removed, or reordered a
    /// list item — not just the ones this type itself performs
    /// (`NoteEditorView.Coordinator.textDidChange` calls this on every
    /// change so a mid-run paste or a deleted item further up the list also
    /// gets renumbered, not only edits that went through `handleReturn`).
    static func renumberRun(near location: Int, in textView: NSTextView) {
        guard let textStorage = textView.textStorage, textStorage.length > 0, location >= 0, location < textStorage.length else { return }
        guard let run = NoteListMarkers.orderedListRun(containing: location, in: textStorage),
              let list = paragraphStyle(at: run[0].location, in: textView)?.textLists.first
        else { return }

        let selectionBefore = textView.selectedRange()
        textStorage.beginEditing()
        let changed = NoteListMarkers.renumber(run: run, list: list, in: textStorage)
        textStorage.endEditing()
        guard changed else { return }

        textView.setSelectedRange(clampedSelection(selectionBefore, in: textStorage))
        textView.didChangeText()
    }

    // MARK: - Shared helpers

    /// Every paragraph range covered by `blockRange`, in document order.
    /// `blockRange` itself may be zero-length (an empty document, or the
    /// caret sitting on an empty final paragraph) — in which case this is
    /// exactly the one paragraph at that location.
    private static func paragraphRanges(in blockRange: NSRange, textStorage: NSTextStorage) -> [NSRange] {
        guard textStorage.length > 0 else { return [NSRange(location: 0, length: 0)] }
        let nsString = textStorage.string as NSString
        var ranges: [NSRange] = []
        var location = blockRange.location
        let end = blockRange.location + blockRange.length
        repeat {
            let range = nsString.paragraphRange(for: NSRange(location: location, length: 0))
            ranges.append(range)
            location = range.location + range.length
        } while location < end
        return ranges
    }

    /// The paragraph style at `location` — from `textStorage` if there's a
    /// character there, otherwise from `typingAttributes`, which is what an
    /// entirely empty document (or the empty end of a non-empty one) has
    /// instead.
    private static func paragraphStyle(at location: Int, in textView: NSTextView) -> NSParagraphStyle? {
        guard let textStorage = textView.textStorage, textStorage.length > 0, location < textStorage.length else {
            return textView.typingAttributes[.paragraphStyle] as? NSParagraphStyle
        }
        return textStorage.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle
    }

    /// The attributes a marker inserted at `location` should carry — the
    /// character already there if any, else `typingAttributes`. Deliberately
    /// never sets an explicit `.foregroundColor`: `NoteRTF` strips that
    /// attribute on every save and load so text follows `NSTextView.textColor`
    /// in dark mode, and a marker with its own hardcoded colour would break
    /// that (see `NoteRTF.rtfdData(from:)`).
    private static func attributes(at location: Int, in textView: NSTextView) -> [NSAttributedString.Key: Any] {
        guard let textStorage = textView.textStorage, textStorage.length > 0, location < textStorage.length else {
            return textView.typingAttributes
        }
        return textStorage.attributes(at: location, effectiveRange: nil)
    }

    /// Renumbering can change a marker's length (e.g. "9." → "10."), which
    /// shifts everything after it — re-clamp a pre-edit selection against
    /// the storage's new length rather than trusting it blindly.
    private static func clampedSelection(_ range: NSRange, in textStorage: NSTextStorage) -> NSRange {
        let maxLocation = textStorage.length
        let location = min(range.location, maxLocation)
        let length = min(range.length, maxLocation - location)
        return NSRange(location: location, length: max(length, 0))
    }
}
