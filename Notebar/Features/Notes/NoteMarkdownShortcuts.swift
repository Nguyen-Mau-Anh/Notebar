import AppKit

/// Deliverable 3: typing `- ` or `* ` at the start of a line starts a
/// bulleted list, and `1. ` starts a numbered one — *in addition* to the
/// formatting bar, not instead of it (spec §6.2b: "discoverability and speed
/// are different needs").
///
/// Hooked from `NoteEditorView.Coordinator.textView(_:shouldChangeTextIn:
/// replacementString:)`, which runs *before* the space that triggers this is
/// actually inserted — returning `false` there suppresses the space
/// entirely, rather than inserting it and then having to undo it.
enum NoteMarkdownShortcuts {
    private static let numberedMarker = try! NSRegularExpression(pattern: "^[0-9]+\\.$")

    /// Returns `true` to let the space insert normally (nothing at the start
    /// of this line looked like a list marker), or `false` if this converted
    /// the line into a list instead. The marker text itself is deleted, not
    /// left behind — `NSTextList` draws its own bullet or number, so a
    /// literal "- " in the text would just be a second, redundant one.
    static func handle(_ textView: NSTextView, range: NSRange, replacement: String?) -> Bool {
        guard replacement == " ", range.length == 0, let textStorage = textView.textStorage else { return true }

        let nsString = textStorage.string as NSString
        let lineRange = nsString.lineRange(for: NSRange(location: range.location, length: 0))
        let markerRange = NSRange(location: lineRange.location, length: range.location - lineRange.location)
        guard markerRange.length > 0 else { return true }
        let marker = nsString.substring(with: markerRange)

        let ordered: Bool
        if marker == "-" || marker == "*" {
            ordered = false
        } else if numberedMarker.firstMatch(in: marker, range: NSRange(location: 0, length: (marker as NSString).length)) != nil {
            ordered = true
        } else {
            return true
        }

        textStorage.beginEditing()
        textStorage.deleteCharacters(in: markerRange)
        textStorage.endEditing()
        textView.setSelectedRange(NSRange(location: markerRange.location, length: 0))

        NoteTextStyling.toggleList(ordered: ordered, in: textView)
        // Bypassed the text view's own editing path above (see
        // `NoteTextStyling`'s doc comment), so nothing has posted the
        // "text changed" notification `Coordinator.textDidChange` relies on
        // to save this edit — trigger it explicitly.
        textView.didChangeText()
        return false
    }
}
