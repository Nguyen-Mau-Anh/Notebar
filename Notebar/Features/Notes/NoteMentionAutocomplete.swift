import AppKit
import Observation
import SwiftUI
import NotebarCore
import NotebarStore

/// One row the `@` autocomplete popover can offer — a note or a task,
/// projected down to exactly what the row needs to render and what
/// `NoteEditorView.Coordinator.insertChip` needs to build a chip (spec §6.4
/// deliverable 3).
struct MentionCandidate: Identifiable, Equatable {
    var id: String
    var type: LinkEntityType
    var title: String
    var updatedAt: Date
}

/// The live bridge between the `@` autocomplete popover (SwiftUI,
/// `MentionPopoverView`) and the `NSTextView` it filters — mirrors
/// `NoteEditingContext`'s role between `FormattingBarView` and the note
/// editor, for the identical reason: the popover is laid out as a sibling
/// view, not a child, of the text view, so both need a shared object to
/// point at rather than holding each other directly. Unlike
/// `NoteEditingContext`, this one also owns the mutation it performs
/// (`select(_:)` edits `textStorage` and writes the chip's `link` row
/// itself) rather than delegating back to the coordinator — there is
/// nothing coordinator-specific about "insert this chip," so keeping it here
/// keeps `NoteEditorView.Coordinator` down to only what needs delegate
/// callbacks: detecting the `@` and forwarding text/selection changes to
/// `refresh()`.
///
/// `NotesTab`'s `NoteEditorContainer` creates a fresh instance per note
/// (`@State`, keyed by `.id(activeID)`, same as `editingContext`), so a
/// mention session never survives a switch to a different note.
@Observable
final class NoteMentionContext {
    weak var textView: NSTextView?
    weak var model: PanelViewModel?
    var noteID: Note.ID = ""

    private(set) var candidates: [MentionCandidate] = []
    private var mentionStartLocation: Int?

    var isActive: Bool { mentionStartLocation != nil }

    /// Called by `NoteEditorView.Coordinator` after every text change and
    /// every selection change (a session must end just as surely when the
    /// caret is *clicked* somewhere else as when it types past a word
    /// boundary — the "clicking away dismisses" half of spec §6.4
    /// deliverable 3). Detects the start of a new session (the character
    /// just before the caret is `@`, and no session is active yet) and, for
    /// an already-active one, re-filters on the text typed since — or ends
    /// it the moment that text contains whitespace, the caret moves in
    /// front of the `@`, or there is a non-empty selection instead of a
    /// caret.
    func refresh() {
        guard let textView else { return }
        let selection = textView.selectedRange()
        guard selection.length == 0 else { cancel(); return }
        let caret = selection.location
        let nsString = textView.string as NSString

        if let start = mentionStartLocation {
            guard caret > start, start + 1 <= nsString.length, caret <= nsString.length else {
                cancel()
                return
            }
            let query = nsString.substring(with: NSRange(location: start + 1, length: caret - start - 1))
            guard !query.contains(where: { $0.isWhitespace || $0.isNewline }) else {
                cancel()
                return
            }
            candidates = model?.mentionCandidates(matching: query) ?? []
        } else if caret > 0, nsString.substring(with: NSRange(location: caret - 1, length: 1)) == "@" {
            mentionStartLocation = caret - 1
            model?.hasOpenOverlay = true
            candidates = model?.mentionCandidates(matching: "") ?? []
        }
    }

    /// Ends the session without inserting anything — Escape
    /// (`NoteEditorView.Coordinator`'s `doCommandBy` handling), the query
    /// growing whitespace, the caret moving away, or the editor tearing
    /// down (`NoteEditorContainer.onDisappear`). A no-op if no session is
    /// active, so callers on a teardown path can call this unconditionally.
    func cancel() {
        guard mentionStartLocation != nil else { return }
        mentionStartLocation = nil
        candidates = []
        model?.hasOpenOverlay = false
    }

    /// Replaces the `@query` text with a chip and writes the backing `link`
    /// row in the same transaction as the note body save (spec §6.4
    /// deliverable 3), via `PanelViewModel.insertLinkChip`.
    func select(_ candidate: MentionCandidate) {
        guard let textView, let model, let start = mentionStartLocation, let textStorage = textView.textStorage else {
            cancel()
            return
        }
        let caret = textView.selectedRange().location
        let mentionRange = NSRange(location: start, length: max(0, caret - start))

        // Ended *before* mutating the text, not after: the replacement
        // below calls `textView.didChangeText()`, which synchronously
        // re-enters `Coordinator.textDidChange` and this method's own
        // `refresh()` before `select(_:)` ever returns. If the session were
        // still "active" at that point, `refresh()` would see a caret that
        // has moved past `start` and try to re-derive a query from the
        // chip's own title — cancelling here first means that re-entrant
        // `refresh()` sees no active session and, since the character now
        // before the caret is the trailing space this inserts (never `@`),
        // starts no new one either.
        cancel()

        let chip = NSMutableAttributedString(string: candidate.title, attributes: NoteFont.typingAttributes)
        let chipRange = NSRange(location: 0, length: chip.length)
        chip.addAttribute(.link, value: LinkURL.url(for: candidate.type, id: candidate.id), range: chipRange)
        NoteChipStyling.apply(to: chip, range: chipRange)
        chip.append(NSAttributedString(string: " ", attributes: NoteFont.typingAttributes))

        textStorage.beginEditing()
        textStorage.replaceCharacters(in: mentionRange, with: chip)
        textStorage.endEditing()

        let newCaret = mentionRange.location + chip.length
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

/// The popover content: every matching note/task, most-recently-updated
/// first, capped in height and scrollable — mirrors `AllNotesPopover`
/// exactly, down to the empty-state copy's tone.
struct MentionPopoverView: View {
    let context: NoteMentionContext

    var body: some View {
        Group {
            if context.candidates.isEmpty {
                Text("No matches")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(Tokens.Space.md)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(context.candidates) { candidate in
                            MentionRow(candidate: candidate) {
                                context.select(candidate)
                            }
                        }
                    }
                }
                .frame(maxHeight: Tokens.Size.mentionPopoverMaxHeight)
            }
        }
        .frame(width: Tokens.Size.mentionPopoverWidth)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.md)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.md)
                .strokeBorder(Color.primary.opacity(0.08))
        )
        .shadow(radius: 8, y: 2)
    }
}

/// One row: a symbol distinguishing note from task, the title, and a
/// relative "updated" timestamp — mirrors `AllNotesRow`.
private struct MentionRow: View {
    let candidate: MentionCandidate
    let onSelect: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: Tokens.Space.sm) {
                Image(systemName: candidate.type == .note ? "doc.text" : "checklist")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 14)

                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.title)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(candidate.updatedAt.formatted(.relative(presentation: .named)))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, Tokens.Space.md)
            .padding(.vertical, Tokens.Space.sm)
            .background(isHovering ? Color.accentColor.opacity(0.08) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel("\(candidate.title), updated \(candidate.updatedAt.formatted(.relative(presentation: .named)))")
    }
}
