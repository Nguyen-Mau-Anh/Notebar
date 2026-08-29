import Foundation
import Observation

/// State shared between `PanelController` (owns the window's geometry and
/// drives it through AppKit) and `RootView` (owns what is drawn inside it).
///
/// `PanelController` flips `isExpanded` in lockstep with the frame it
/// animates the window toward — the full panel or the collapsed handle — and
/// `RootView` reads it to pick which of the two to render. `selection` lives
/// here rather than as `RootView`'s own `@State` because the collapsed
/// handle must show the icon of the *currently selected* tab, and
/// `PanelController` has no other way to know what that is. Note-tab state
/// (`notes`, `activeNoteID`) and Task state (`taskGroups`) live here for the
/// same reason: they are UI state, not AppKit state, but `PanelController`
/// still needs `isPinned` to forward into `PanelContext`.
///
/// Everything below is in-memory only — no database yet. SQLite lands behind
/// repository protocols in a later task without needing this UI to change.
@Observable
final class PanelViewModel {
    var isExpanded = false
    var selection: AppTab = .notes

    /// Drives `PanelContext.isPinned` via `PanelController`, which observes
    /// this property and forwards it. The suppression behaviour itself
    /// already lives in `PanelMachine.shouldCollapse` — this is only the
    /// missing path from SwiftUI into it.
    var isPinned = false

    /// Toggles the expanded panel between its normal size and half the
    /// screen (spec §6.1). This has no `PanelContext` counterpart — size is
    /// a `PanelController` framing concern, not a state-machine concern, and
    /// is deliberately independent of `isPinned`: maximizing does not imply
    /// pinning, so a maximized-but-unpinned panel still collapses on cursor
    /// exit. `PanelController` observes this the same way it observes
    /// `isPinned`, and re-animates to the new frame if the panel is
    /// currently on screen.
    var isMaximized = false

    // MARK: - Collapse-suppression signals (spec §4.4)
    //
    // `PanelController` mirrors these into `PanelContext` the same way it
    // already mirrors `isPinned` — see `observePin()`. They live here, not on
    // `PanelContext` directly, for the same reason `isPinned` does: this is
    // the only channel SwiftUI has into the state machine.

    /// A text editor in the panel holds first responder. Wired from
    /// `NoteEditorView`'s `@FocusState`.
    var isEditorFocused = false

    /// When the user last typed a character, or nil if never this session.
    /// A timestamp rather than a duration so it never ages by itself —
    /// `PanelController` computes `msSinceLastKeystroke` from this at the
    /// moment it snapshots `PanelContext`, since `PanelMachine` must not read
    /// a clock.
    var lastKeystrokeAt: Date?

    /// A drag is in flight. No drag source exists yet (M2); settable now so
    /// the channel is ready when one does.
    var isDragging = false

    /// A menu, popover, or sheet is open. No overlay exists yet; settable
    /// now so the channel is ready when one does.
    var hasOpenOverlay = false

    // MARK: - Notes

    var notes: [Note] = []
    var activeNoteID: Note.ID?

    /// Creates a new untitled note and makes it the active tab — the
    /// zero-friction-capture path the toolbar's `+` exists for.
    func createNote() {
        let note = Note()
        notes.append(note)
        activeNoteID = note.id
    }

    /// Closes a note tab. If it was active, falls back to the note that took
    /// its place in the strip, or the new last tab, or nil once the last
    /// note is gone — `NotesTab` shows the empty state in that case.
    func closeNote(id: Note.ID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes.remove(at: index)
        guard activeNoteID == id else { return }
        activeNoteID = notes.indices.contains(index) ? notes[index].id : notes.last?.id
    }

    // MARK: - Tasks

    var taskGroups: [TaskGroup] = TaskGroup.seeded

    var totalTaskCount: Int {
        taskGroups.reduce(0) { $0 + $1.tasks.count }
    }

    /// Appends a new task into the first group. Groups are fixed and
    /// dragging between them is M2 scope — see spec §6.4a.
    func addTask() {
        guard !taskGroups.isEmpty else { return }
        taskGroups[0].tasks.append(TaskItem(title: "New task"))
    }
}
