import SwiftUI

/// The seven formatting operations the bar (spec §6.2b) and the markdown
/// input shortcuts (deliverable 3, `NoteMarkdownShortcuts`) both drive, in
/// the bar's left-to-right order. Spec §6.2b also lists a Checklist button,
/// but checklists need a clickable `NSTextAttachment` — genuinely fiddly,
/// and a separate task — so there is deliberately no `.checklist` case and
/// no eighth button: a control that does nothing would be worse than one
/// that isn't there.
enum NoteTextStyle: CaseIterable {
    case bold, italic, code, heading1, heading2, bulletedList, numberedList

    var symbol: String {
        switch self {
        case .bold: "bold"
        case .italic: "italic"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .heading1: "textformat.size.larger"
        case .heading2: "textformat.size"
        case .bulletedList: "list.bullet"
        case .numberedList: "list.number"
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
        }
    }
}
