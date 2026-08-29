import AppKit
import SwiftUI
import NotebarCore
import NotebarStore

/// `NSTextView` renders every character with no `.foregroundColor` attribute
/// (the whole storage, per `NoteFont.typingAttributes` and `NoteRTF`'s
/// stripping) using its own `textColor` — but `textColor` is a plain stored
/// property, not something that re-resolves itself. AppKit calls
/// `viewDidChangeEffectiveAppearance()` on a view whenever its
/// `effectiveAppearance` changes, which covers both ways the app's
/// appearance can change: `PanelViewModel.applyTheme`/`AppDelegate` setting
/// `NSApp.appearance` directly when the user picks a Theme, and macOS itself
/// flipping light/dark while Theme is "System" (no explicit `NSApp.appearance`
/// override in that case to shadow the system value). Re-applying
/// `.labelColor` here and marking the view dirty is what makes already-typed
/// text actually repaint in the new colour instead of sitting frozen at
/// whatever `.labelColor` last resolved to when it was drawn.
private final class NoteTextView: NSTextView {
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        textColor = .labelColor
        insertionPointColor = .labelColor
        needsDisplay = true
    }
}

/// The seam `NotesTab`'s plain-text placeholder was built behind precisely
/// for this swap (spec §6.2): an `NSTextView`, wrapped in `NSViewRepresentable`,
/// replacing the SwiftUI `TextEditor` that used to sit here. `NSTextView`
/// gives full control over attributes and first-responder behaviour that
/// `TextEditor` never exposed — exactly what rich text and the formatting
/// bar (`FormattingBarView`) need.
///
/// Storage moved from `body` as `String` to `Note.bodyRTF` as a flat RTFD
/// blob (`NoteRTF`) — RTFD rather than plain RTF so a pasted or dragged
/// image (spec §6.2c) survives the round trip — with `Note.bodyPlain`
/// regenerated in the same transaction so FTS cannot drift (spec §5) — see
/// `Coordinator.textDidChange`.
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
    let mentionContext: NoteMentionContext

    func makeNSView(context: Context) -> NSScrollView {
        // Apple's own convenience for pairing a text view with a correctly
        // configured scroll view — resizing masks, container tracking, and
        // min/max size are all handled by this rather than hand-rolled. Its
        // doc comment guarantees the document view is an instance of the
        // receiver, so calling it on `NoteTextView` (rather than plain
        // `NSTextView`) is what wires the appearance-change override in.
        let scrollView = NoteTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.isEditable = true
        textView.drawsBackground = false
        textView.allowsUndo = true
        // Spec §6.2c: lets a pasted or dragged image land as an
        // `NSTextAttachment` instead of being ignored or interpreted as a
        // file-path string — `NSTextView` does the rest of the work itself.
        textView.importsGraphics = true
        // Without these, `NSTextView` falls back to hard black regardless of
        // appearance. `labelColor` is a dynamic system colour that resolves
        // per appearance at load time; `NoteTextView.viewDidChangeEffectiveAppearance`
        // above is what keeps it correct afterward, on a live theme switch.
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.textContainerInset = NSSize(width: Tokens.Space.md, height: Tokens.Space.md)
        textView.textContainer?.widthTracksTextView = true
        textView.typingAttributes = NoteFont.typingAttributes

        if let note = model.notes.first(where: { $0.id == noteID }) {
            // `.link` survives the RTFD round trip but `.foregroundColor`
            // does not (`NoteRTF` strips it so ordinary text always tracks
            // `textColor`) — `NoteChipStyling.restyled` is what puts a
            // chip's accent colour back before anything is ever drawn. See
            // that type's doc comment for why this is done here, on load,
            // rather than exempting chip runs from the strip.
            let attributedString = NoteChipStyling.restyled(NoteRTF.attributedString(fromRTFD: note.bodyRTF))
            textView.textStorage?.setAttributedString(attributedString)
        }

        context.coordinator.model = model
        context.coordinator.noteID = noteID
        context.coordinator.editingContext = editingContext
        context.coordinator.mentionContext = mentionContext
        editingContext.textView = textView
        editingContext.refreshActiveStyles()
        mentionContext.textView = textView
        mentionContext.model = model
        mentionContext.noteID = noteID

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
        weak var mentionContext: NoteMentionContext?

        /// Fires for every edit — typed, pasted, or a direct `textStorage`
        /// mutation followed by an explicit `didChangeText()` (formatting
        /// bar toggles, `NoteMarkdownShortcuts`) — so this is the one place
        /// that regenerates `bodyPlain` from the live attributed string and
        /// schedules the debounced save (spec §5, deliverable 4).
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView, let model else { return }
            model.lastKeystrokeAt = .now
            // Fires after both a paste and a completed drag (spec §6.2c),
            // so this is the one place any newly embedded image gets
            // downscaled and fit to the container's width before the body
            // below is captured for saving.
            NoteImageEmbedding.normalizeAttachments(in: textView)
            // Safety net for spec §6.2d's renumbering requirement: catches
            // every edit that adds or removes a list item *except* Return
            // (handled directly in `shouldChangeTextIn`, below, since that's
            // the one edit `NoteListEditing.handleReturn` performs itself) —
            // a pasted block of items, or an item deleted via an ordinary
            // selection-and-delete, still lands here.
            NoteListEditing.renumberRun(near: textView.selectedRange().location, in: textView)
            let attributedString = textView.attributedString()
            model.updateNoteBody(
                id: noteID,
                bodyRTF: NoteRTF.rtfdData(from: attributedString),
                bodyPlain: NoteRTF.plainText(from: attributedString)
            )
            editingContext?.refreshActiveStyles()
            // Spec §6.4 deliverable 3: detects an `@` just typed, or keeps
            // an already-open mention session filtered by what's been typed
            // since. Every edit runs through here, `NoteMentionContext`
            // itself decides whether any of it is mention-relevant.
            mentionContext?.refresh()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            editingContext?.refreshActiveStyles()
            // The caret can move with no text change at all (a click, an
            // arrow key) — a mention session must end just as surely on
            // that as on typing past a word boundary, spec §6.4's "clicking
            // away dismisses."
            mentionContext?.refresh()
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
        /// is actually inserted. Return gets the same "intercept before the
        /// default edit happens" treatment for spec §6.2d: inside a list
        /// item, `NoteListEditing.handleReturn` performs the edit itself
        /// (ending the list on an empty item, or starting the next one with
        /// its own marker) and this returns `false` so the plain "\n" the
        /// key press would otherwise insert never lands on top of it.
        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            if replacementString == "\n", NoteListEditing.handleReturn(in: textView, range: affectedCharRange) {
                return false
            }
            return NoteMarkdownShortcuts.handle(textView, range: affectedCharRange, replacement: replacementString)
        }

        /// Spec §6.4 deliverable 3: "Escape ... dismisses without
        /// inserting." `PanelController.installEscapeMonitor` already lets
        /// Escape reach the editor whenever it holds first responder — see
        /// that method's doc comment — so this is where it actually lands.
        /// Consumed (returns `true`) only while a mention session is open;
        /// otherwise falls through to `NSTextView`'s own default handling
        /// (`false`), unchanged from before this feature existed.
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.cancelOperation(_:)), mentionContext?.isActive == true else {
                return false
            }
            mentionContext?.cancel()
            return true
        }

        /// Spec §6.4 deliverable 4: clicking a chip opens its target.
        /// `NSTextView` already routes a click on a `.link` run here — no
        /// custom hit-testing needed, exactly the payoff spec §6.4 calls out
        /// for building chips as a `.link` attribute rather than an
        /// `NSTextAttachment`. A `link` this doesn't recognize (a foreign
        /// scheme, or a malformed `notebar://` URL) is left for `NSTextView`
        /// to handle its own way (`false`) — in practice, none exist, since
        /// every chip this editor ever inserts comes from `LinkURL.url(for:id:)`.
        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            guard let url = link as? URL, let target = LinkURL.parse(url) else { return false }
            model?.openLinkTarget(target)
            return true
        }
    }
}
