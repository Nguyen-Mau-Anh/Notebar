import Foundation
import SwiftUI
import UniformTypeIdentifiers
import NotebarCore

struct TasksTab: View {
    let model: PanelViewModel

    var body: some View {
        VStack(spacing: 0) {
            TabToolbar {
                HStack(spacing: Tokens.Space.xs) {
                    Text("Tasks")
                        .font(.system(size: 13, weight: .semibold))
                    Text("\(model.totalTaskCount)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            } right: {
                ToolbarActionButton(symbol: "plus", accessibilityLabel: "New task") {
                    model.addTask()
                }
            }

            if model.totalTaskCount == 0 {
                PlaceholderTab(
                    symbol: "checklist",
                    title: "Tasks",
                    detail: "Click + to add your first task."
                )
            } else {
                board
            }
        }
    }

    private var board: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.lg) {
                ForEach(model.taskColumnGroups) { group in
                    TaskGroupSection(model: model, group: group)
                }
            }
            .padding(Tokens.Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// One status column: a header plus its cards, and a drop target for
/// dragging a card in from another group (spec §6.3a). The true side-by-side
/// / collapsible-group board layouts (spec §6.3) are still a later task; this
/// is a simple grouped list.
private struct TaskGroupSection: View {
    let model: PanelViewModel
    let group: PanelViewModel.TaskColumnGroup

    /// Highlights the group while a card is dragged over it — the drop
    /// target's own visual feedback, distinct from `isDragging` (which lives
    /// on `model` and only gates panel collapse).
    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.sm) {
            HStack(spacing: Tokens.Space.xs) {
                Text(group.column.name)
                    .font(.system(size: 12, weight: .semibold))
                Text("\(group.tasks.count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                // Without a `Spacer`, this row is only as wide as its two
                // text labels — which, for an empty group with no cards
                // beneath it to stretch the section, left the whole drop
                // target a sliver in the leading corner. Pushing the row
                // itself to fill the width is what `.frame(maxWidth:)`
                // below relies on to make the *section* full-width too.
                Spacer(minLength: 0)
            }

            if group.tasks.isEmpty {
                emptyPlaceholder
            } else {
                ForEach(group.tasks) { task in
                    TaskCardView(model: model, task: task)
                }
            }
        }
        .padding(Tokens.Space.xs)
        // Full width regardless of content: a group with cards already
        // stretched to fit the widest card, but an empty group (or one
        // with only a short header) would otherwise shrink-wrap, leaving
        // most of the board's width outside the droppable area.
        .frame(maxWidth: .infinity, alignment: .leading)
        // The droppable region is this exact shape, not whatever glyphs
        // happen to be painted inside it — same reasoning as the
        // `.contentShape(Rectangle())` every custom button needs, applied
        // here to a drop target instead of a tap target.
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.md)
                .fill(isDropTargeted ? Color.accentColor.opacity(0.08) : .clear)
        )
        // `[.plainText]` matches what `TaskCardView.onDrag` registers
        // (an `NSString` of the task id). A drop that lands here always
        // returns `true` — SwiftUI only calls this when the drag is over
        // this group's own bounds, so there's nothing to reject — while a
        // release outside every group's bounds never reaches any
        // `onDrop` at all and is cancelled by construction, per spec §6.3a.
        // That bounds check now covers the header row and the empty-state
        // placeholder too, since both sit inside this same modified view.
        .onDrop(of: [.plainText], isTargeted: $isDropTargeted) { providers in
            guard let provider = providers.first else { return false }
            provider.loadObject(ofClass: NSString.self) { reading, _ in
                guard let taskID = reading as? String else { return }
                DispatchQueue.main.async {
                    model.moveTask(id: taskID, toColumnID: group.column.id)
                }
            }
            return true
        }
    }

    /// An empty group has no cards to give the section height, so without
    /// this it collapses to just its header row — nowhere to aim a drop.
    /// `Tokens.Size.taskEmptyGroupMinHeight` reserves roughly one card's
    /// worth of space, dashed at the `radius.md` corner treatment the
    /// design spec calls for on drop placeholders (§1.5). It stays faint at
    /// rest and turns clearly visible for the whole duration of any
    /// drag (`model.isDragging`) rather than only while hovered, so every
    /// valid target is visible as soon as a card is picked up.
    private var emptyPlaceholder: some View {
        RoundedRectangle(cornerRadius: Tokens.Radius.md)
            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            .foregroundStyle(.secondary.opacity(model.isDragging ? 0.5 : 0.12))
            .frame(maxWidth: .infinity, minHeight: Tokens.Size.taskEmptyGroupMinHeight)
    }
}

/// One task card. Collapsed, it shows only its title; clicking its header
/// expands it in place to reveal an always-editable detail field and its
/// metadata, capped at `Tokens.Size.taskDetailMaxHeight` with internal
/// scroll (spec §6.3a). Renaming, deleting, and dragging between groups all
/// live here too, matching the note-tab interactions this mirrors
/// (`NotesTab.NoteTabButton`).
private struct TaskCardView: View {
    let model: PanelViewModel
    let task: TaskItem

    @State private var isEditingTitle = false
    @State private var draftTitle = ""
    @FocusState private var isTitleFieldFocused: Bool
    @FocusState private var isDetailFieldFocused: Bool

    private var isExpanded: Bool { model.expandedTaskID == task.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isExpanded {
                expandedContent
            }
        }
        .padding(Tokens.Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.md)
                .fill(.quaternary.opacity(0.4))
        )
        .contextMenu {
            Button("Rename", action: beginRename)
            Button("Delete", role: .destructive) { model.deleteTask(id: task.id) }
        }
    }

    /// Title plus the expand/collapse chevron. Grabbing this row is also
    /// what starts a drag — a drag handle on the title, not the whole card,
    /// so a click-drag inside the expanded detail editor selects text
    /// instead of picking the card up.
    private var header: some View {
        HStack(spacing: Tokens.Space.xs) {
            if isEditingTitle {
                // Committing on Return and on blur both funnel through
                // `commitRename()`, guarded by `isEditingTitle` so a
                // Return-then-blur sequence can't double-commit. Escape
                // reaches `onExitCommand` rather than being swallowed by
                // `PanelController`'s escape monitor: this field's field
                // editor is an `NSTextView`, which the monitor's
                // `panel.firstResponder is NSText` check lets through
                // undisturbed — the same reasoning `NoteTabButton` documents.
                TextField("Untitled task", text: $draftTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($isTitleFieldFocused)
                    .onSubmit(commitRename)
                    .onExitCommand(perform: cancelRename)
                    .onChange(of: isTitleFieldFocused) { _, focused in
                        if !focused { commitRename() }
                    }
            } else {
                Text(task.title)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
        }
        .contentShape(Rectangle())
        // Double-tap gesture attached before the single-tap one, on the
        // same view, so SwiftUI resolves a double-click as rename rather
        // than as two expand/collapse toggles — the exact pattern
        // `NoteTabButton` uses for the identical ambiguity.
        .onTapGesture(count: 2, perform: beginRename)
        .onTapGesture { model.toggleTaskExpansion(id: task.id) }
        .onDrag {
            model.beginTaskDrag()
            return NSItemProvider(object: NSString(string: task.id))
        }
    }

    /// Capped at `Tokens.Size.taskDetailMaxHeight` and internally scrolling
    /// — without the cap, a long detail would push every group below it far
    /// down the list and the board would stop being a board.
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            Divider()
                .padding(.vertical, Tokens.Space.xs)

            TextEditor(text: detailBinding)
                .font(.system(size: 12))
                .scrollContentBackground(.hidden)
                .frame(maxHeight: Tokens.Size.taskDetailMaxHeight)
                .focused($isDetailFieldFocused)
                .onChange(of: isDetailFieldFocused) { _, focused in
                    // Blur flushes any debounced save immediately, same as
                    // `NoteEditorView` — losing focus is exactly the moment
                    // the user might switch away, so a pending write can't
                    // be left dangling.
                    if !focused { model.flushPendingTaskSave(id: task.id) }
                }

            metadata

            BacklinksSection(model: model, target: LinkTarget(type: .task, id: task.id))
        }
        .padding(.top, Tokens.Space.xs)
    }

    private var metadata: some View {
        HStack(spacing: Tokens.Space.sm) {
            Text("Updated \(task.updatedAt.formatted(.relative(presentation: .named)))")
            if let dueAt = task.dueAt {
                Text("· Due \(dueAt.formatted(.relative(presentation: .named)))")
            }
            if let completedAt = task.completedAt {
                Text("· Completed \(completedAt.formatted(.relative(presentation: .named)))")
            }
            if task.priority != 0 {
                Text("· Priority \(task.priority)")
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
    }

    /// Reads through `model.task(withID:)` rather than the `task` this view
    /// was handed, mirroring `NotesTab.bodyBinding(for:)`: the source of
    /// truth is whatever was last written into the model, not a copy
    /// captured at some earlier render.
    private var detailBinding: Binding<String> {
        Binding(
            get: { model.task(withID: task.id)?.detailPlain ?? task.detailPlain },
            set: { model.updateTaskDetail(id: task.id, detail: $0) }
        )
    }

    private func beginRename() {
        draftTitle = task.title
        isEditingTitle = true
        isTitleFieldFocused = true
    }

    private func commitRename() {
        guard isEditingTitle else { return }
        isEditingTitle = false
        model.renameTask(id: task.id, title: draftTitle)
    }

    private func cancelRename() {
        isEditingTitle = false
    }
}
