import SwiftUI

struct RootView: View {
    let model: PanelViewModel

    var body: some View {
        Group {
            if model.isExpanded {
                expandedBody
            } else {
                CollapsedHandle(tab: model.selection)
            }
        }
    }

    private var expandedBody: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.width < Tokens.Size.compactBreakpoint

            HStack(spacing: 0) {
                TabRail(
                    selection: Binding(
                        get: { model.selection },
                        set: { model.selection = $0 }
                    ),
                    isPinned: Binding(
                        get: { model.isPinned },
                        set: { model.isPinned = $0 }
                    ),
                    isMaximized: Binding(
                        get: { model.isMaximized },
                        set: { model.isMaximized = $0 }
                    ),
                    isCompact: isCompact,
                    isDragging: model.isDragging,
                    onCollapse: { model.requestCollapse?() }
                )

                Divider()

                Group {
                    switch model.selection {
                    case .notes:    NotesTab(model: model)
                    case .tasks:    TasksTab(model: model)
                    case .settings: SettingsTab(model: model)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(.regularMaterial)
        // Left corners rounded at the panel's own radius, right corners
        // square: the panel is flush to the screen's right edge, same
        // treatment as `CollapsedHandle` below but at `radius.panel` rather
        // than `radius.md`.
        .clipShape(UnevenRoundedRectangle(
            topLeadingRadius: Tokens.Radius.panel,
            bottomLeadingRadius: Tokens.Radius.panel,
            bottomTrailingRadius: 0,
            topTrailingRadius: 0
        ))
    }
}

/// What the panel shows at rest, flush to the right screen edge, once it has
/// retreated instead of vanishing. `PanelController` sizes the window to
/// exactly `Tokens.Size.handleWidth` x `Tokens.Size.handleHeight`, so this
/// view only needs to fill that frame.
private struct CollapsedHandle: View {
    let tab: AppTab

    var body: some View {
        // Left corners rounded, right corners square: the handle reads as
        // something tucked half behind the screen edge rather than a free
        // floating pill. "Left"/"right" here are the physical screen edge,
        // not layout direction — the panel is always flush to the display's
        // right edge regardless of locale.
        UnevenRoundedRectangle(
            topLeadingRadius: Tokens.Radius.md,
            bottomLeadingRadius: Tokens.Radius.md,
            bottomTrailingRadius: 0,
            topTrailingRadius: 0
        )
        .fill(.regularMaterial)
        .overlay {
            Image(systemName: tab.symbol)
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
        }
        .frame(width: Tokens.Size.handleWidth, height: Tokens.Size.handleHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tab.title)
    }
}

#Preview("Expanded") {
    let model = PanelViewModel()
    model.isExpanded = true
    return RootView(model: model).frame(width: 340, height: 745)
}

#Preview("Collapsed handle") {
    RootView(model: PanelViewModel()).frame(width: 60, height: 100)
}
