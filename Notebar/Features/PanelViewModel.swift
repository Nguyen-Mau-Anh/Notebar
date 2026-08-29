import AppKit
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
/// (`notes`, `activeNoteID`) and Task state (`taskColumnGroups`) live here for the
/// same reason: they are UI state, not AppKit state, but `PanelController`
/// still needs `isPinned` to forward into `PanelContext`.
///
/// Notes, the open-tab strip, and tasks all persist through
/// `NoteRepository` / `OpenTabRepository` / `TaskRepository`
/// (`NotebarStore`'s GRDB implementations by default).
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

    /// The rail's bottom-anchored collapse button (spec §6.1) calls this.
    /// `PanelController.start()` installs it as `{ [weak self] in self?.toggle() }`
    /// once the controller exists — the view is built before the controller
    /// is, so it cannot be handed `toggle()` directly. Weak so this model
    /// (which outlives no one in particular) can never keep the controller
    /// alive; if nothing has installed it yet the button is inert rather
    /// than crashing.
    ///
    /// This is a one-shot action, not state to mirror, so it is a plain
    /// closure rather than something `PanelController` observes with
    /// `observeModel` — there is nothing here for `withObservationTracking`
    /// to track.
    var requestCollapse: (() -> Void)?

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

    /// A drag is in flight. Set by `beginTaskDrag()`/`endTaskDrag()`, the
    /// task board's card-drag handlers (spec §6.3a) — the first real
    /// producer of this signal.
    var isDragging = false

    /// A menu, popover, or sheet is open. No overlay exists yet; settable
    /// now so the channel is ready when one does.
    var hasOpenOverlay = false

    /// Polls for the mouse-up that ends a task-card drag. Neither `.onDrag`
    /// nor `.onDrop` gives SwiftUI a callback for "the drag session ended" —
    /// only for a successful drop on a registered target — so a drag
    /// released outside every group (spec §6.3a: "cancelled, not dropped")
    /// would otherwise never clear `isDragging`, permanently blocking the
    /// panel from collapsing (`PanelMachine.shouldCollapse` treats it as a
    /// hard invariant). Polling `NSEvent.pressedMouseButtons`, like
    /// `CursorMonitor` polls `NSEvent.mouseLocation`, needs no
    /// Accessibility/Input Monitoring permission — unlike
    /// `NSEvent.addGlobalMonitorForEvents`, deliberately avoided for the
    /// same reason (spec section 4.2) — so this guarantees the flag clears
    /// on both the successful and the cancelled path without that prompt.
    private var dragEndPollTimer: Timer?

    /// Called from a task card's `.onDrag` closure, exactly when a drag
    /// begins — the one synchronous hook that API offers.
    func beginTaskDrag() {
        isDragging = true
        dragEndPollTimer?.invalidate()
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            guard NSEvent.pressedMouseButtons == 0 else { return }
            self?.endTaskDrag()
        }
        RunLoop.main.add(timer, forMode: .common)
        dragEndPollTimer = timer
    }

    /// Clears `isDragging`, however the drag ended — dropped on a group or
    /// released outside every one. `beginTaskDrag()`'s poll timer calls this
    /// the moment the mouse button lifts; a successful drop's own handler
    /// calls it too, so the flag clears immediately rather than waiting out
    /// the next 50ms tick.
    func endTaskDrag() {
        dragEndPollTimer?.invalidate()
        dragEndPollTimer = nil
        isDragging = false
    }

    // MARK: - Notes

    /// Notes and tasks both save 400ms after the last keystroke, or
    /// immediately on blur (`flushPendingSave`/`flushPendingTaskSave`) — not
    /// on every keystroke, which would mean a disk write per character
    /// typed. One shared constant rather than two identical ones.
    private static let saveDebounceInterval: TimeInterval = 0.4

    private let noteRepository: NoteRepository
    private let openTabRepository: OpenTabRepository
    private let taskRepository: TaskRepository

    /// All repository writes happen off the main thread, so a debounced
    /// save (or the open-tab replace it triggers) never blocks typing or
    /// panel animation. `.utility`: these are small local writes, not
    /// user-interactive work, but should still complete promptly.
    private let persistenceQueue = DispatchQueue(label: "com.anhnm.notebar.persistence", qos: .utility)

    private var pendingSaves: [Note.ID: DispatchWorkItem] = [:]

    var notes: [Note] = []
    var activeNoteID: Note.ID?

    init(noteRepository: NoteRepository, openTabRepository: OpenTabRepository, taskRepository: TaskRepository) {
        self.noteRepository = noteRepository
        self.openTabRepository = openTabRepository
        self.taskRepository = taskRepository
        loadPersistedState()
        loadTasks()
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
        self.init(
            noteRepository: repositories.notes,
            openTabRepository: repositories.openTabs,
            taskRepository: repositories.tasks
        )
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
    /// normally removes only the tab, not the note itself — the note stays
    /// in the store.
    ///
    /// The exception is a note that is still `isEmptyAndUntitled`: an
    /// untouched note carries no information, so keeping it around would
    /// only clutter the all-notes list, and closing its tab deletes it
    /// outright instead. Any note with a title or a body is the user's
    /// content, so this check runs on the in-memory `notes` entry — which is
    /// always current, unlike the repository row until the next debounced
    /// save — before anything is flushed, and closing a tab and deleting a
    /// note stay distinct operations for every note that has any content.
    func closeNote(id: Note.ID) {
        if let note = notes.first(where: { $0.id == id }), note.isEmptyAndUntitled {
            deleteNote(id: id)
            return
        }
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

    /// Every note in the database, most recently updated first — the
    /// backing list for the All-notes menu's popover (spec §6.2a).
    /// Deliberately reads `noteRepository` directly rather than `notes` (the
    /// open-tab strip): closing a tab does not delete its note, so the note
    /// stays in the store and out of `notes` with no other way back in —
    /// this is that way back in, and it must include notes never opened
    /// this session too.
    func allNotesByRecency() -> [Note] {
        let all = (try? noteRepository.all()) ?? []
        return all.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Opens a note as the active tab, creating the tab if it was closed —
    /// the All-notes menu's row action (spec §6.2a). Takes the whole `Note`
    /// rather than just an id since the caller already has it from
    /// `allNotesByRecency()`; this only appends it to the strip if it isn't
    /// there already.
    func openNote(_ note: Note) {
        flushAllPendingSaves()
        if !notes.contains(where: { $0.id == note.id }) {
            notes.append(note)
        }
        activeNoteID = note.id
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
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.saveDebounceInterval, execute: work)
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
    /// a time but this makes no assumption about that. Also flushes any
    /// pending task-detail save, for the identical reason.
    func flushAllPendingSaves() {
        for id in pendingSaves.keys {
            flushPendingSave(id: id)
        }
        for id in pendingTaskSaves.keys {
            flushPendingTaskSave(id: id)
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

    /// One status column paired with its tasks, in the shape `TasksTab`
    /// renders — spec §6.3a's board groups cards by column, and this is
    /// that grouping precomputed from `TaskRepository.columns()` /
    /// `.all()` rather than left for the view to redo on every render.
    struct TaskColumnGroup: Identifiable {
        var id: BoardColumn.ID { column.id }
        var column: BoardColumn
        var tasks: [TaskItem]
    }

    var taskColumnGroups: [TaskColumnGroup] = []

    /// The single card currently expanded in place (spec §6.3a). At most one
    /// at a time: setting a new id is what collapses whichever one was open,
    /// since there is nowhere else the "which card is expanded" fact lives.
    var expandedTaskID: TaskItem.ID?

    private var pendingTaskSaves: [TaskItem.ID: DispatchWorkItem] = [:]

    var totalTaskCount: Int {
        taskColumnGroups.reduce(0) { $0 + $1.tasks.count }
    }

    /// Loads every column and task from the store and regroups them —
    /// called once at startup (mirroring `loadPersistedState()`) and again
    /// after any write below, so `taskColumnGroups` always reflects what was
    /// actually persisted rather than an optimistic local guess.
    private func loadTasks() {
        guard let columns = try? taskRepository.columns(), let tasks = try? taskRepository.all() else { return }
        let tasksByColumn = Dictionary(grouping: tasks, by: \.columnID)
        taskColumnGroups = columns.map { column in
            TaskColumnGroup(column: column, tasks: tasksByColumn[column.id] ?? [])
        }
    }

    /// Appends a new task into the first column (Queue, spec §6.3a's
    /// `backlogKind` — dragging into other columns is the next task, not
    /// this one).
    func addTask() {
        guard let firstColumn = taskColumnGroups.first?.column else { return }
        guard (try? taskRepository.create(title: "New task", columnID: firstColumn.id)) != nil else { return }
        loadTasks()
    }

    /// The current in-memory copy of a task, looked up by id rather than
    /// held as a stale value — mirrors `bodyBinding(for:)`'s reasoning in
    /// `NotesTab` so a card's detail editor always reads what was actually
    /// last written, not a copy captured at some earlier render.
    func task(withID id: TaskItem.ID) -> TaskItem? {
        taskColumnGroups.lazy.flatMap(\.tasks).first { $0.id == id }
    }

    private func taskIndexPath(for id: TaskItem.ID) -> (group: Int, task: Int)? {
        for (groupIndex, group) in taskColumnGroups.enumerated() {
            if let taskIndex = group.tasks.firstIndex(where: { $0.id == id }) {
                return (groupIndex, taskIndex)
            }
        }
        return nil
    }

    /// Expands a card in place, or collapses it if it was already the one
    /// expanded — the card header's click handler (spec §6.3a).
    func toggleTaskExpansion(id: TaskItem.ID) {
        expandedTaskID = (expandedTaskID == id) ? nil : id
    }

    /// Renames a task and persists the new title immediately — one discrete
    /// commit (Return, blur, or the context menu's Rename), not a stream of
    /// keystrokes, so nothing to debounce, mirroring `renameNote`. Unlike a
    /// note's fallback to "Untitled", an empty title here falls back to the
    /// task's *previous* title (spec §6.3a): simply not applying a blank
    /// edit leaves the existing title in place. Persists only what's already
    /// in memory, so a rename never touches the detail a debounced save
    /// hasn't flushed yet.
    func renameTask(id: TaskItem.ID, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let (groupIndex, taskIndex) = taskIndexPath(for: id) else { return }
        taskColumnGroups[groupIndex].tasks[taskIndex].title = trimmed
        let task = taskColumnGroups[groupIndex].tasks[taskIndex]
        persistenceQueue.async { [taskRepository] in
            try? taskRepository.update(task)
        }
    }

    /// Deletes a task outright — the card's right-click "Delete". Cancels
    /// any pending debounced detail save first, for the same reason
    /// `deleteNote` does: writing a stale update immediately before the
    /// delete would be wasted at best and a lost-update race at worst.
    func deleteTask(id: TaskItem.ID) {
        pendingTaskSaves.removeValue(forKey: id)?.cancel()
        if expandedTaskID == id { expandedTaskID = nil }
        for index in taskColumnGroups.indices {
            taskColumnGroups[index].tasks.removeAll { $0.id == id }
        }
        persistenceQueue.async { [taskRepository] in
            try? taskRepository.delete(id: id)
        }
    }

    /// The single path every edit to a task's detail goes through: updates
    /// the in-memory copy immediately and schedules a debounced save,
    /// mirroring `updateNoteBody` exactly — same debounce interval, same
    /// "no edit mode" reasoning (spec §6.3a).
    func updateTaskDetail(id: TaskItem.ID, detail: String) {
        guard let (groupIndex, taskIndex) = taskIndexPath(for: id) else { return }
        taskColumnGroups[groupIndex].tasks[taskIndex].detailPlain = detail
        scheduleTaskSave(id: id)
    }

    private func scheduleTaskSave(id: TaskItem.ID) {
        pendingTaskSaves[id]?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.persistTask(id: id) }
        pendingTaskSaves[id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.saveDebounceInterval, execute: work)
    }

    /// Saves a task immediately, bypassing the debounce — called on the
    /// detail editor's blur, so a pause shorter than the debounce interval
    /// never loses a keystroke. Mirrors `flushPendingSave`.
    func flushPendingTaskSave(id: TaskItem.ID) {
        guard let work = pendingTaskSaves.removeValue(forKey: id) else { return }
        work.cancel()
        persistTask(id: id)
    }

    private func persistTask(id: TaskItem.ID) {
        pendingTaskSaves[id] = nil
        guard let task = task(withID: id) else { return }
        persistenceQueue.async { [taskRepository] in
            try? taskRepository.update(task)
        }
    }

    /// Moves a dropped card into `columnID`, appended after that column's
    /// current last task (spec §6.3a). `GRDBTaskRepository.move` already
    /// writes the fresh fractional `sort_order` and owns the `completedAt`
    /// stamping rule entirely — this only ever supplies the destination and
    /// reloads, never reimplements either. Reordering within a column isn't
    /// this deliverable's ask (only moving *between* groups is), so `before`
    /// is always nil and `after` is always the destination's current last
    /// task.
    func moveTask(id: TaskItem.ID, toColumnID columnID: BoardColumn.ID) {
        guard let destination = taskColumnGroups.first(where: { $0.column.id == columnID }) else { return }
        let lastTaskID = destination.tasks.last?.id
        guard (try? taskRepository.move(id: id, columnID: columnID, before: nil, after: lastTaskID)) != nil else { return }
        loadTasks()
    }
}
