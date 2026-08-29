import AppKit
import Observation

/// The live bridge between the formatting bar (SwiftUI, `FormattingBarView`)
/// and the `NSTextView` it formats (AppKit, wrapped by `NoteEditorView`).
/// Neither side can hold the other directly — the text view doesn't exist
/// until `NoteEditorView.makeNSView` runs, by which point the bar has
/// already been laid out beside it as a sibling, not a child, view — so both
/// instead point at this one shared object. `NotesTab`'s `NoteEditorContainer`
/// creates a fresh instance per note (keyed by `.id(activeID)`, same as the
/// editor itself), so no button state ever leaks from one note into the next.
@Observable
final class NoteEditingContext {
    weak var textView: NSTextView?
    private(set) var activeStyles: Set<NoteTextStyle> = []

    /// Called by `NoteEditorView.Coordinator` on every selection and text
    /// change, so the bar always reflects where the caret actually is.
    func refreshActiveStyles() {
        guard let textView else { return }
        activeStyles = NoteTextStyling.activeStyles(in: textView)
    }

    /// The formatting bar's button action, and each button's `⌘B`/`⌘I`/etc.
    /// `.keyboardShortcut` (`FormattingBarView`), both call this.
    func toggle(_ style: NoteTextStyle) {
        guard let textView else { return }
        // A click on the bar would otherwise leave one of *its* buttons as
        // first responder rather than the text view. Restoring it keeps the
        // edit landing where the user expects, and keeps
        // `PanelController.installEscapeMonitor`'s `firstResponder is
        // NSText` check seeing the editor, not some other view.
        textView.window?.makeFirstResponder(textView)

        switch style {
        case .bold: NoteTextStyling.toggleBold(in: textView)
        case .italic: NoteTextStyling.toggleItalic(in: textView)
        case .code: NoteTextStyling.toggleCode(in: textView)
        case .heading1: NoteTextStyling.toggleHeading(1, in: textView)
        case .heading2: NoteTextStyling.toggleHeading(2, in: textView)
        case .bulletedList: NoteTextStyling.toggleList(ordered: false, in: textView)
        case .numberedList: NoteTextStyling.toggleList(ordered: true, in: textView)
        }

        // `NoteTextStyling`'s functions edit `textStorage` directly, which
        // doesn't go through the text view's own editing path and so never
        // posts the "text changed" notification `Coordinator.textDidChange`
        // relies on to save this edit — trigger it explicitly. That in turn
        // calls `refreshActiveStyles()` too, making the call below
        // redundant but harmless; it stays so this method's own effect on
        // the bar never depends on that indirect path.
        textView.didChangeText()
        refreshActiveStyles()
    }
}
