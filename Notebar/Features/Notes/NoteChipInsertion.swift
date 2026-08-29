import AppKit
import NotebarCore
import NotebarStore

/// The one place a link chip is actually built and written into a note
/// (spec §6.4): a run carrying `candidate.title`, styled by
/// `NoteChipStyling.apply`, tagged with the `notebar://` URL
/// `textView(_:clickedOnLink:at:)` parses back on click, followed by a
/// trailing space so typing right after a chip never inherits its link/accent
/// attributes.
///
/// Two callers replace two different kinds of range with the same chip:
/// `NoteMentionContext.select(_:)` replaces the `@query` text the user just
/// typed, and `NoteEditorView.Coordinator`'s drag-and-drop handling (spec
/// §6.4 deliverable 2) replaces a zero-length range at wherever a dropped
/// task card landed. Neither duplicates this logic — a chip means the same
/// thing, and writes the same `link` row, no matter which path produced it.
enum NoteChipInsertion {
    static func insert(
        candidate: MentionCandidate,
        replacing range: NSRange,
        in textView: NSTextView,
        model: PanelViewModel,
        noteID: Note.ID
    ) {
        guard let textStorage = textView.textStorage else { return }

        let chip = NSMutableAttributedString(string: candidate.title, attributes: NoteFont.typingAttributes)
        let chipRange = NSRange(location: 0, length: chip.length)
        chip.addAttribute(.link, value: LinkURL.url(for: candidate.type, id: candidate.id), range: chipRange)
        NoteChipStyling.apply(to: chip, range: chipRange)
        chip.append(NSAttributedString(string: " ", attributes: NoteFont.typingAttributes))

        textStorage.beginEditing()
        textStorage.replaceCharacters(in: range, with: chip)
        textStorage.endEditing()

        let newCaret = range.location + chip.length
        textView.setSelectedRange(NSRange(location: newCaret, length: 0))
        // Reset so the character typed right after the chip isn't itself
        // linked/accent-coloured — `replaceCharacters(in:with:)` otherwise
        // leaves `typingAttributes` wherever the chip's own attributes left
        // it.
        textView.typingAttributes = NoteFont.typingAttributes
        textView.didChangeText()

        let attributedString = textView.attributedString()
        model.insertLinkChip(
            noteID: noteID,
            bodyRTF: NoteRTF.rtfdData(from: attributedString),
            bodyPlain: NoteRTF.plainText(from: attributedString),
            destination: LinkTarget(type: candidate.type, id: candidate.id)
        )
    }
}
