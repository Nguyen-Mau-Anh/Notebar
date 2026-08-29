import SwiftUI

struct NotesTab: View {
    let model: PanelViewModel

    var body: some View {
        VStack(spacing: 0) {
            TabToolbar {
                NoteTabStrip(
                    notes: model.notes,
                    activeID: model.activeNoteID,
                    onSelect: { model.activeNoteID = $0 },
                    onClose: { model.closeNote(id: $0) }
                )
            } right: {
                ToolbarActionButton(symbol: "plus", accessibilityLabel: "New note") {
                    model.createNote()
                }
            }

            if let activeID = model.activeNoteID, model.notes.contains(where: { $0.id == activeID }) {
                NoteEditorView(text: bodyBinding(for: activeID), model: model)
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
    /// every later index, but the id stays stable.
    private func bodyBinding(for id: Note.ID) -> Binding<String> {
        Binding(
            get: { model.notes.first(where: { $0.id == id })?.body ?? "" },
            set: { newValue in
                guard let index = model.notes.firstIndex(where: { $0.id == id }) else { return }
                model.notes[index].body = newValue
            }
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

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(notes) { note in
                    NoteTabButton(
                        title: note.title,
                        isActive: note.id == activeID,
                        onSelect: { onSelect(note.id) },
                        onClose: { onClose(note.id) }
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

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: Tokens.Space.xs) {
            Text(title)
                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? Color.primary : Color.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            if isHovering || isActive {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close note")
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
        .onTapGesture(perform: onSelect)
        .onHover { isHovering = $0 }
        .accessibilityLabel(title)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
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

    @FocusState private var isFocused: Bool

    var body: some View {
        TextEditor(text: $text)
            .font(.system(size: 14))
            .scrollContentBackground(.hidden)
            .padding(Tokens.Space.md)
            .focused($isFocused)
            .onChange(of: isFocused) { _, newValue in
                model.isEditorFocused = newValue
            }
            .onChange(of: text) { _, _ in
                model.lastKeystrokeAt = .now
            }
    }
}
