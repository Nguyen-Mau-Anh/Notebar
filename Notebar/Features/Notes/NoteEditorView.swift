import AppKit
import SwiftUI
import NotebarCore
import NotebarStore

/// The seam `NotesTab`'s plain-text placeholder was built behind precisely
/// for this swap (spec §6.2): an `NSTextView`, wrapped in `NSViewRepresentable`,
/// replacing the SwiftUI `TextEditor` that used to sit here. `NSTextView`
/// gives full control over attributes and first-responder behaviour that
/// `TextEditor` never exposed — exactly what rich text and the formatting
/// bar (`FormattingBarView`) need.
///
/// Storage moved from `body` as `String` to `Note.bodyRTF` as an RTF blob
/// (`NoteRTF`), with `Note.bodyPlain` regenerated in the same transaction so
/// FTS cannot drift (spec §5) — see `Coordinator.textDidChange`.
///
/// Also the real source for two of `PanelContext`'s collapse-suppression
/// signals (spec §4.4): `Coordinator.textDidBeginEditing`/`textDidEndEditing`
/// mirror focus into `model.isEditorFocused`, and every text change stamps
/// `model.lastKeystrokeAt`. `PanelController` picks both up the same way it
/// already picks up `isPinned` — see `observeEditorFocused()`/
/// `observeLastKeystroke()`. `NSTextView` conforms to `NSText`, the same
/// protocol the old `TextEditor`'s backing view did, so
/// `PanelController.installEscapeMonitor`'s `panel.firstResponder is NSText`
/// check keeps working unchanged.
struct NoteEditorView: NSViewRepresentable {
    let model: PanelViewModel
    let noteID: Note.ID
    let editingContext: NoteEditingContext

    func makeNSView(context: Context) -> NSScrollView {
        // Apple's own convenience for pairing a text view with a correctly
        // configured scroll view — resizing masks, container tracking, and
        // min/max size are all handled by this rather than hand-rolled.
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.isEditable = true
        textView.drawsBackground = false
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: Tokens.Space.md, height: Tokens.Space.md)
        textView.textContainer?.widthTracksTextView = true
        textView.typingAttributes = NoteFont.typingAttributes

        if let note = model.notes.first(where: { $0.id == noteID }) {
            let attributedString = NoteRTF.attributedString(from: note.bodyRTF)
            textView.textStorage?.setAttributedString(attributedString)
        }

        context.coordinator.model = model
        context.coordinator.noteID = noteID
        context.coordinator.editingContext = editingContext
        editingContext.textView = textView
        editingContext.refreshActiveStyles()

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        // Deliberately empty: once created, the text view is the source of
        // truth for its own content — `Coordinator.textDidChange` is the
        // only thing that ever writes a note's body back out. Pushing
        // SwiftUI's copy of `model.notes` into the text view on every
        // re-render would fight the user's own typing with a stale
        // snapshot instead of leaving it alone.
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var model: PanelViewModel?
        var noteID: Note.ID = ""
        weak var editingContext: NoteEditingContext?

        /// Fires for every edit — typed, pasted, or a direct `textStorage`
        /// mutation followed by an explicit `didChangeText()` (formatting
        /// bar toggles, `NoteMarkdownShortcuts`) — so this is the one place
        /// that regenerates `bodyPlain` from the live attributed string and
        /// schedules the debounced save (spec §5, deliverable 4).
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView, let model else { return }
            model.lastKeystrokeAt = .now
            let attributedString = textView.attributedString()
            model.updateNoteBody(
                id: noteID,
                bodyRTF: NoteRTF.data(from: attributedString),
                bodyPlain: NoteRTF.plainText(from: attributedString)
            )
            editingContext?.refreshActiveStyles()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            editingContext?.refreshActiveStyles()
        }

        /// `NSTextView.becomeFirstResponder()` posts this when the view is
        /// editable, which it always is here — the reliable, delegate-only
        /// way to track focus without subclassing `NSTextView` just to
        /// override `becomeFirstResponder()`.
        func textDidBeginEditing(_ notification: Notification) {
            model?.isEditorFocused = true
        }

        /// Blur flushes any debounced save immediately (spec deliverable 4:
        /// "save on a 400ms pause and on blur") — losing focus is exactly
        /// the moment the user might switch away or quit, so a pending
        /// write can't be left dangling.
        func textDidEndEditing(_ notification: Notification) {
            model?.isEditorFocused = false
            if let model {
                model.flushPendingSave(id: noteID)
            }
        }

        /// Deliverable 3's markdown shortcuts: `- `/`* ` or `1. ` at the
        /// start of a line, checked and applied before the triggering space
        /// is actually inserted.
        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            NoteMarkdownShortcuts.handle(textView, range: affectedCharRange, replacement: replacementString)
        }
    }
}
