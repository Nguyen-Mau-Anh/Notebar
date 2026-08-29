import Foundation
import Observation
import NotebarCore
import NotebarStore

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
/// Notes and the open-tab strip now persist through `NoteRepository` /
/// `OpenTabRepository` (`NotebarStore`'s GRDB implementations by default).
/// Task state remains in-memory only — SQLite lands behind repository
/// protocols for tasks in a later task without needing this UI to change.
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

    /// Notes save 400ms after the last keystroke, or immediately on blur
    /// (`flushPendingSave`) — not on every keystroke, which would mean a
    /// disk write per character typed.
    private static let noteSaveDebounceInterval: TimeInterval = 0.4

    private let noteRepository: NoteRepository
    private let openTabRepository: OpenTabRepository

    /// All repository writes happen off the main thread, so a debounced
    /// save (or the open-tab replace it triggers) never blocks typing or
    /// panel animation. `.utility`: these are small local writes, not
    /// user-interactive work, but should still complete promptly.
    private let persistenceQueue = DispatchQueue(label: "com.anhnm.notebar.persistence", qos: .utility)

    private var pendingSaves: [Note.ID: DispatchWorkItem] = [:]

    var notes: [Note] = []
    var activeNoteID: Note.ID?

    init(noteRepository: NoteRepository, openTabRepository: OpenTabRepository) {
        self.noteRepository = noteRepository
        self.openTabRepository = openTabRepository
        loadPersistedState()
    }

    /// Convenience for SwiftUI previews and any caller that doesn't need a
    /// specific store: an in-memory database, migrated the same way the
    /// real one is. The app target wires up the on-disk store explicitly in
    /// `AppDelegate` instead of relying on this.
    convenience init() {
        // In-memory database creation only fails on a GRDB/SQLite
        // programming error (a bad migration), not an environment problem —
        // there's no disk I/O to fail here, so surfacing that as a crash
        // during preview/test setup is preferable to swallowing it.
        let repositories = try! NotebarDatabase.openInMemory()
        self.init(noteRepository: repositories.notes, openTabRepository: repositories.openTabs)
    }

    /// Restores `notes` and `activeNoteID` from whatever was open when the
    /// app last quit (spec §2 decision 3). A note with no corresponding
    /// open-tab row — because its tab was closed — stays in the database
    /// but out of the strip; there is no notes browser yet to reopen it
    /// from, which is a known gap until one exists.
    private func loadPersistedState() {
        guard let allNotes = try? noteRepository.all() else { return }
        let notesByID = Dictionary(uniqueKeysWithValues: allNotes.map { ($0.id, $0) })
        let tabs = (try? openTabRepository.all()) ?? []
        notes = tabs.compactMap { notesByID[$0.refID] }
        activeNoteID = tabs.first(where: { $0.isActive })?.refID
    }

    /// Creates a new untitled note and makes it the active tab — the
    /// zero-friction-capture path the toolbar's `+` exists for. Persisted
    /// immediately: an empty note is cheap to write and should survive a
    /// quit even before the user types anything.
    func createNote() {
        guard let note = try? noteRepository.create() else { return }
        notes.append(note)
        activeNoteID = note.id
        persistOpenTabs()
    }

    /// Closes a note tab. If it was active, falls back to the note that took
    /// its place in the strip, or the new last tab, or nil once the last
    /// note is gone — `NotesTab` shows the empty state in that case. Closing
    /// removes the tab, not the note itself — the note stays in the store.
    func closeNote(id: Note.ID) {
        flushAllPendingSaves()
        removeTab(id: id)
    }

    /// Deletes a note outright — the tab's right-click "Delete", which
    /// removes the note from the database too, not just its tab (unlike
    /// `closeNote`). Cancels any pending debounced save for this note first
    /// rather than flushing it: writing a body update immediately before
    /// deleting the row would be wasted work at best and a lost-update race
    /// against the delete at worst.
    func deleteNote(id: Note.ID) {
        pendingSaves.removeValue(forKey: id)?.cancel()
        removeTab(id: id)
        persistenceQueue.async { [noteRepository] in
            try? noteRepository.delete(id: id)
        }
    }

    /// Renames a note and persists the new title immediately. Unlike
    /// `updateNoteBody`, a rename is one discrete commit (Return, blur, or
    /// the context menu's Rename), not a stream of keystrokes, so there is
    /// nothing to debounce. An empty or all-whitespace title falls back to
    /// "Untitled" so a tab can never go blank — the inline editor also
    /// guards this, but this is the actual source of truth.
    func renameNote(id: Note.ID, title: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        notes[index].title = trimmed.isEmpty ? "Untitled" : trimmed
        let note = notes[index]
        persistenceQueue.async { [noteRepository] in
            try? noteRepository.update(note)
        }
    }

    /// Removes a tab from the strip and repoints `activeNoteID` if needed.
    /// Shared by `closeNote` (note stays in the store) and `deleteNote`
    /// (note is also removed from the store) — both need identical tab
    /// bookkeeping.
    private func removeTab(id: Note.ID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes.remove(at: index)
        if activeNoteID == id {
            activeNoteID = notes.indices.contains(index) ? notes[index].id : notes.last?.id
        }
        persistOpenTabs()
    }

    /// Selects a note tab. A dedicated method rather than a plain settable
    /// property (unlike `isPinned`/`isMaximized`) because selecting a tab
    /// also changes which tab is `isActive` in the persisted open-tab set.
    func selectNote(id: Note.ID) {
        flushAllPendingSaves()
        activeNoteID = id
        persistOpenTabs()
    }

    /// The single path every edit to a note's body goes through: updates the
    /// in-memory copy immediately (so the UI never lags) and schedules a
    /// debounced save of the persisted copy.
    func updateNoteBody(id: Note.ID, body: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].body = body
        scheduleSave(id: id)
    }

    private func scheduleSave(id: Note.ID) {
        pendingSaves[id]?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.persistNote(id: id) }
        pendingSaves[id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.noteSaveDebounceInterval, execute: work)
    }

    /// Saves a note immediately, bypassing the debounce, and cancels any
    /// timer that was still pending for it. Called on editor blur and tab
    /// switch/close, so a pause shorter than the debounce interval never
    /// loses a keystroke.
    func flushPendingSave(id: Note.ID) {
        guard let work = pendingSaves.removeValue(forKey: id) else { return }
        work.cancel()
        persistNote(id: id)
    }

    /// Called on quit (`AppDelegate.applicationWillTerminate`) and whenever
    /// the active tab changes, since only one note is ever being edited at
    /// a time but this makes no assumption about that.
    func flushAllPendingSaves() {
        for id in pendingSaves.keys {
            flushPendingSave(id: id)
        }
    }

    private func persistNote(id: Note.ID) {
        pendingSaves[id] = nil
        guard let note = notes.first(where: { $0.id == id }) else { return }
        persistenceQueue.async { [noteRepository] in
            try? noteRepository.update(note)
        }
    }

    /// Replaces the entire persisted open-tab set with the current strip.
    /// Called on structural changes only (create/close/select) — never per
    /// keystroke — so a full replace is cheap enough not to matter.
    private func persistOpenTabs() {
        let tabs = notes.enumerated().map { index, note in
            OpenTab(
                kind: OpenTab.noteKind,
                refID: note.id,
                sortOrder: Double(index),
                isActive: note.id == activeNoteID
            )
        }
        persistenceQueue.async { [openTabRepository] in
            try? openTabRepository.replaceAll(tabs)
        }
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
