import SwiftUI
import NotebarCore

/// The 28x28pt chevron button immediately left of the Notes toolbar's `+`
/// (spec §6.2a). Opens a popover listing every note in the database — not
/// just the ones with open tabs — so a note whose tab was closed still has a
/// route back into the strip; see `PanelViewModel.allNotesByRecency()`.
///
/// This is also the first real producer of `hasOpenOverlay`: it has been
/// wired through `PanelViewModel` into `PanelContext` since the
/// collapse-policy work, but nothing has ever set it until now.
/// `PanelMachine.shouldCollapse` already treats it as a hard invariant, so
/// setting it true while the popover is open (and false the instant it
/// closes, however it closes — row selection, click-away, or Escape) is all
/// that's needed here.
///
/// Known limitation: unlike `isEditorFocused` (reconciled against
/// `panel.firstResponder` in `PanelController.send(_:)`), there is no
/// equivalent "reality" to check a SwiftUI `.popover` against from outside
/// the view — no reliable, public way to ask "is a popover currently
/// presented" independent of the `isShowingMenu` binding that drives it.
/// `hasOpenOverlay` therefore stays event-driven, and the `.onDisappear`
/// below is a mitigation, not a guarantee: it only catches this view being
/// torn down (e.g. a future tab switch away from Notes) while its own
/// popover is open. If SwiftUI ever tears this view down without calling
/// `onDisappear`, `hasOpenOverlay` can still stick `true` forever, exactly
/// like the bug this fix is patterned after.
struct AllNotesMenuButton: View {
    let model: PanelViewModel

    @State private var isShowingMenu = false

    var body: some View {
        ToolbarActionButton(symbol: "chevron.down", accessibilityLabel: "All notes") {
            isShowingMenu = true
        }
        .popover(isPresented: $isShowingMenu) {
            AllNotesPopover(model: model, dismiss: { isShowingMenu = false })
        }
        .onChange(of: isShowingMenu) { _, isOpen in
            model.hasOpenOverlay = isOpen
        }
        .onDisappear {
            // Mitigation for this view being torn down while its popover is
            // still open — see the type doc comment above. Not a guarantee.
            if isShowingMenu {
                model.hasOpenOverlay = false
            }
        }
    }
}

/// Popover content: every note, most recently updated first, capped in
/// height (`Tokens.Size.allNotesPopoverMaxHeight`) and scrollable so a large
/// note count never produces a popover taller than the screen.
private struct AllNotesPopover: View {
    let model: PanelViewModel
    let dismiss: () -> Void

    var body: some View {
        let allNotes = model.allNotesByRecency()

        Group {
            if allNotes.isEmpty {
                Text("No notes yet")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(Tokens.Space.md)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(allNotes) { note in
                            AllNotesRow(
                                note: note,
                                isOpen: model.notes.contains { $0.id == note.id },
                                onSelect: {
                                    model.openNote(note)
                                    dismiss()
                                }
                            )
                        }
                    }
                }
                .frame(maxHeight: Tokens.Size.allNotesPopoverMaxHeight)
            }
        }
        .frame(width: Tokens.Size.allNotesPopoverWidth)
    }
}

/// One row: title, a relative "updated" timestamp, and — for a note already
/// open as a tab — a small accent dot ahead of the title.
private struct AllNotesRow: View {
    let note: Note
    let isOpen: Bool
    let onSelect: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: Tokens.Space.sm) {
                Circle()
                    .fill(isOpen ? Color.accentColor : .clear)
                    .frame(width: Tokens.Size.allNotesOpenDotSize, height: Tokens.Size.allNotesOpenDotSize)

                VStack(alignment: .leading, spacing: 2) {
                    Text(note.displayTitle)
                        .font(.system(size: 12, weight: isOpen ? .semibold : .regular))
                        .foregroundStyle(isOpen ? Color.accentColor : Color.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(note.updatedAt.formatted(.relative(presentation: .named)))
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
        .accessibilityLabel("\(note.displayTitle), updated \(note.updatedAt.formatted(.relative(presentation: .named)))")
    }
}
