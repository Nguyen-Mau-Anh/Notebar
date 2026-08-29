import SwiftUI
import NotebarCore

struct NotesTab: View {
    let model: PanelViewModel

    var body: some View {
        VStack(spacing: 0) {
            TabToolbar {
                NoteTabStrip(
                    notes: model.notes,
                    activeID: model.activeNoteID,
                    onSelect: { model.selectNote(id: $0) },
                    onClose: { model.closeNote(id: $0) },
                    onRename: { model.renameNote(id: $0, title: $1) },
                    onDelete: { model.deleteNote(id: $0) }
                )
            } right: {
                HStack(spacing: Tokens.Space.xs) {
                    AllNotesMenuButton(model: model)
                    ToolbarActionButton(symbol: "plus", accessibilityLabel: "New note") {
                        model.createNote()
                    }
                }
            }

            if let activeID = model.activeNoteID, model.notes.contains(where: { $0.id == activeID }) {
                NoteEditorView(text: bodyBinding(for: activeID), model: model, noteID: activeID)
                    .id(activeID)
            } else {
                PlaceholderTab(
                    symbol: "doc.text",
                    title: "Notes",
                    detail: "Click + to start your first note."
                )
            }
        }
    }

    /// Keyed by id rather than array index: closing an earlier tab shifts
    /// every later index, but the id stays stable. The setter routes through
    /// `updateNoteBody` rather than mutating `model.notes` directly so every
    /// keystroke also schedules the debounced save (spec deliverable 4).
    private func bodyBinding(for id: Note.ID) -> Binding<String> {
        Binding(
            get: { model.notes.first(where: { $0.id == id })?.body ?? "" },
            set: { newValue in model.updateNoteBody(id: id, body: newValue) }
        )
    }
}

/// The horizontal, Notepad++-style tab strip that sits in the toolbar's left
/// slot (screen spec §4.1). Scrolls horizontally when the open notes overflow
/// the available width.
private struct NoteTabStrip: View {
    let notes: [Note]
    let activeID: Note.ID?
    let onSelect: (Note.ID) -> Void
    let onClose: (Note.ID) -> Void
    let onRename: (Note.ID, String) -> Void
    let onDelete: (Note.ID) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(notes) { note in
                    NoteTabButton(
                        title: note.displayTitle,
                        isActive: note.id == activeID,
                        onSelect: { onSelect(note.id) },
                        onClose: { onClose(note.id) },
                        onRename: { onRename(note.id, $0) },
                        onDelete: { onDelete(note.id) }
                    )
                }
            }
        }
    }
}

private struct NoteTabButton: View {
    let title: String
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let onRename: (String) -> Void
    let onDelete: () -> Void

    @State private var isHovering = false
    @State private var isEditing = false
    @State private var draftTitle = ""
    @FocusState private var isTitleFieldFocused: Bool

    var body: some View {
        HStack(spacing: Tokens.Space.xs) {
            // The close button sits before the title (user report: it used
            // to trail the label), so every tab reads "× Title".
            if isHovering || isActive {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close note")
            }

            if isEditing {
                // Committing on Return (`onSubmit`) and on blur
                // (`isTitleFieldFocused` going false) both funnel through
                // `commitRename()`, which is itself guarded by `isEditing`
                // so a Return-then-blur sequence can't double-commit.
                // Escape reaches `onExitCommand` rather than being
                // swallowed by `PanelController`'s escape monitor: this
                // field's field editor is an `NSTextView`, which the
                // monitor's `panel.firstResponder is NSText` check lets
                // through undisturbed (see `installEscapeMonitor`).
                TextField("Untitled", text: $draftTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                    .focused($isTitleFieldFocused)
                    .onSubmit(commitRename)
                    .onExitCommand(perform: cancelRename)
                    .onChange(of: isTitleFieldFocused) { _, focused in
                        if !focused { commitRename() }
                    }
            } else {
                Text(title)
                    .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(minWidth: Tokens.Size.noteTabMinWidth, maxWidth: Tokens.Size.noteTabMaxWidth, alignment: .leading)
        .padding(.horizontal, Tokens.Space.xs)
        .padding(.vertical, Tokens.Space.xs)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.sm)
                .fill(isActive ? Color.accentColor.opacity(0.12) : (isHovering ? Color.accentColor.opacity(0.04) : .clear))
        )
        .contentShape(Rectangle())
        // Double-tap gesture attached before the single-tap one so SwiftUI
        // resolves a double-click as rename rather than as two selects.
        .onTapGesture(count: 2, perform: beginRename)
        .onTapGesture(perform: onSelect)
        .onHover { isHovering = $0 }
        .accessibilityLabel(title)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
        .contextMenu {
            Button("Rename", action: beginRename)
            Button("Delete", role: .destructive, action: onDelete)
        }
    }

    private func beginRename() {
        draftTitle = title
        isEditing = true
        isTitleFieldFocused = true
    }

    private func commitRename() {
        guard isEditing else { return }
        isEditing = false
        onRename(draftTitle)
    }

    private func cancelRename() {
        isEditing = false
    }
}

/// The seam for the note body editor. A SwiftUI `TextEditor` over a plain
/// `String` for this slice; the spec's rich-text `NSTextView` wrapper (spec
/// §6.2) is a later task, and this is the only view that will need to change
/// when it lands.
///
/// Also the real source for two of `PanelContext`'s collapse-suppression
/// signals (spec §4.4): focus mirrors into `model.isEditorFocused` via
/// `@FocusState`, and every text change stamps `model.lastKeystrokeAt`.
/// `PanelController` picks both up the same way it already picks up
/// `isPinned` — see `observeEditorFocused()`/`observeLastKeystroke()`.
struct NoteEditorView: View {
    @Binding var text: String
    let model: PanelViewModel
    let noteID: Note.ID

    @FocusState private var isFocused: Bool

    var body: some View {
        TextEditor(text: $text)
            .font(.system(size: 14))
            .scrollContentBackground(.hidden)
            .padding(Tokens.Space.md)
            .focused($isFocused)
            .onChange(of: isFocused) { _, newValue in
                model.isEditorFocused = newValue
                // Blur flushes any debounced save immediately (spec
                // deliverable 4: "save on a 400ms pause and on blur") —
                // losing focus is exactly the moment the user might switch
                // away or quit, so a pending write can't be left dangling.
                if !newValue {
                    model.flushPendingSave(id: noteID)
                }
            }
            .onChange(of: text) { _, _ in
                model.lastKeystrokeAt = .now
            }
    }
}
