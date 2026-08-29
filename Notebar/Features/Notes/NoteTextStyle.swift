import SwiftUI

/// The eight formatting operations the bar (spec §6.2b) and the markdown
/// input shortcuts (deliverable 3, `NoteMarkdownShortcuts`) both drive, in
/// the bar's left-to-right order.
///
/// `.checklist` was deferred when this list first shipped, because a
/// checkbox needs a clickable element, not just an attribute — see
/// `NoteListEditing.handleChecklistClick` and `NoteChecklistStyling` for how
/// that's actually done (a checklist is a list whose marker is a checkbox
/// glyph, reusing `NoteListMarkers`/`NoteListEditing` rather than building a
/// parallel mechanism).
enum NoteTextStyle: CaseIterable {
    case bold, italic, code, heading1, heading2, bulletedList, numberedList, checklist

    var symbol: String {
        switch self {
        case .bold: "bold"
        case .italic: "italic"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .heading1: "textformat.size.larger"
        case .heading2: "textformat.size"
        case .bulletedList: "list.bullet"
        case .numberedList: "list.number"
        case .checklist: "checklist"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .bold: "Bold"
        case .italic: "Italic"
        case .code: "Inline code"
        case .heading1: "Heading 1"
        case .heading2: "Heading 2"
        case .bulletedList: "Bulleted list"
        case .numberedList: "Numbered list"
        case .checklist: "Checklist"
        }
    }

    /// Matches spec §6.2b's table exactly. Installed as SwiftUI
    /// `.keyboardShortcut`s on the bar's buttons (`FormattingBarView`)
    /// rather than an `NSEvent` monitor: those fire whenever the enclosing
    /// window is key, regardless of which view currently holds first
    /// responder, so `⌘B` works while the note editor's `NSTextView` is
    /// focused without this needing to know that view exists.
    var keyEquivalent: (key: Character, modifiers: EventModifiers) {
        switch self {
        case .bold: ("b", [.command])
        case .italic: ("i", [.command])
        case .code: ("c", [.command, .shift])
        case .heading1: ("1", [.command, .option])
        case .heading2: ("2", [.command, .option])
        case .bulletedList: ("8", [.command, .shift])
        case .numberedList: ("7", [.command, .shift])
        case .checklist: ("9", [.command, .shift])
        }
    }
}
