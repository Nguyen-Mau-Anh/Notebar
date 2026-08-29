import SwiftUI

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
                ForEach(model.taskGroups) { group in
                    TaskGroupSection(group: group)
                }
            }
            .padding(Tokens.Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// One collapsible-in-M2 status column, rendered here as a simple grouped
/// list — the true side-by-side / collapsible-group board layouts (spec
/// §6.3) are M2 scope, as is dragging a card between groups.
private struct TaskGroupSection: View {
    let group: TaskGroup

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.sm) {
            HStack(spacing: Tokens.Space.xs) {
                Text(group.name)
                    .font(.system(size: 12, weight: .semibold))
                Text("\(group.tasks.count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            ForEach(group.tasks) { task in
                Text(task.title)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .padding(Tokens.Space.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: Tokens.Radius.md)
                            .fill(.quaternary.opacity(0.4))
                    )
            }
        }
    }
}
