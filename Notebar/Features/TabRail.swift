import SwiftUI
import UniformTypeIdentifiers

struct TabRail: View {
    @Binding var selection: AppTab
    @Binding var isPinned: Bool
    @Binding var isMaximized: Bool
    let isCompact: Bool

    /// A task-card drag is in flight (`PanelViewModel.isDragging`). Gates
    /// `TabRailButton`'s spring-load-to-switch below — see that type's doc
    /// comment for why dragging a card onto a note needs this at all.
    let isDragging: Bool

    /// Calls `PanelViewModel.requestCollapse`. A plain closure, not a
    /// binding, because collapsing is a one-shot action, not state this view
    /// owns or mirrors.
    let onCollapse: () -> Void

    var body: some View {
        VStack(spacing: Tokens.Space.xs) {
            ControlRow(isPinned: $isPinned, isMaximized: $isMaximized)

            Divider()

            ForEach(AppTab.allCases) { tab in
                TabRailButton(
                    tab: tab,
                    isSelected: selection == tab,
                    isCompact: isCompact,
                    isDragging: isDragging
                ) {
                    selection = tab
                }
            }
            Spacer()

            Divider()

            CollapseButton(action: onCollapse)
        }
        .padding(.top, Tokens.Space.md)
        .frame(width: isCompact ? Tokens.Size.railWidthCompact : Tokens.Size.railWidth)
        .frame(maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }
}

/// The 56x32pt control row above the three tabs (spec §6.1): pin on the
/// left, maximize on the right, each a 24x24pt toggle with `Space.xs` (4pt)
/// between them. Deliberately smaller and unlabelled so the row does not
/// read as a fourth tab — these change the panel's *behaviour and size*, not
/// its content. The two toggles are independent: maximizing does not imply
/// pinning, so the user can combine them or use either alone.
private struct ControlRow: View {
    @Binding var isPinned: Bool
    @Binding var isMaximized: Bool

    var body: some View {
        HStack(spacing: Tokens.Space.xs) {
            PinToggle(isPinned: $isPinned)
            MaximizeToggle(isMaximized: $isMaximized)
        }
        .frame(width: Tokens.Size.railWidth, height: Tokens.Size.controlRowHeight)
    }
}

/// Toggling this flows into `PanelController.isPinned`, which
/// `PanelMachine.shouldCollapse` already treats as an absolute veto — this
/// button is the only piece that was missing.
private struct PinToggle: View {
    @Binding var isPinned: Bool

    var body: some View {
        Button {
            isPinned.toggle()
        } label: {
            Image(systemName: isPinned ? "pin.fill" : "pin")
                .font(.system(size: 15))
                .foregroundStyle(isPinned ? Color.accentColor : Color.secondary)
                .frame(width: Tokens.Size.controlToggleSize, height: Tokens.Size.controlToggleSize)
                .background(
                    RoundedRectangle(cornerRadius: Tokens.Radius.sm)
                        .fill(isPinned ? Color.accentColor.opacity(0.10) : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPinned ? "Unpin panel" : "Pin panel")
        .accessibilityAddTraits(isPinned ? [.isSelected] : [])
    }
}

/// Toggling this flows into `PanelViewModel.isMaximized`, which
/// `PanelController` observes to switch the expanded panel between its
/// normal size and half the screen (spec §6.1). Independent of pin: a
/// maximized panel still collapses on cursor exit unless also pinned.
private struct MaximizeToggle: View {
    @Binding var isMaximized: Bool

    var body: some View {
        Button {
            isMaximized.toggle()
        } label: {
            Image(systemName: isMaximized ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 15))
                .foregroundStyle(isMaximized ? Color.accentColor : Color.secondary)
                .frame(width: Tokens.Size.controlToggleSize, height: Tokens.Size.controlToggleSize)
                .background(
                    RoundedRectangle(cornerRadius: Tokens.Radius.sm)
                        .fill(isMaximized ? Color.accentColor.opacity(0.10) : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isMaximized ? "Restore panel size" : "Maximize panel")
        .accessibilityAddTraits(isMaximized ? [.isSelected] : [])
    }
}

/// The 56x32pt control pinned to the bottom of the rail, below the three
/// tabs and separated from them by a hairline (spec §6.1). Dismisses the
/// panel immediately without the user moving the cursor off it — the case
/// it exists for is a **pinned** panel the user is actively working in, since
/// pinning defeats every cursor-driven collapse and previously left only
/// Escape, the menu bar item, or the global hotkey, all of which require
/// leaving the mouse.
///
/// `action` is `PanelViewModel.requestCollapse`, which resolves to
/// `PanelController.toggle()` → `.toggleRequested`. `PanelMachine` handles
/// `(.expanded, .toggleRequested)` independently of `shouldCollapse`, the
/// same way it handles Escape, so this overrides pin without unpinning it:
/// pin state survives the collapse, and the next expand is still pinned.
///
/// Unlike the pin and maximize toggles, this control has no persistent
/// "on" state to color permanently — it is a momentary action — so hover is
/// tracked locally to drive the same secondary → accent step they use.
private struct CollapseButton: View {
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.right.2")
                .font(.system(size: 15))
                .foregroundStyle(isHovering ? Color.accentColor : Color.secondary)
                .frame(width: Tokens.Size.railWidth, height: Tokens.Size.controlRowHeight)
                .background(
                    RoundedRectangle(cornerRadius: Tokens.Radius.sm)
                        .fill(isHovering ? Color.accentColor.opacity(0.08) : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel("Collapse panel")
    }
}

/// Spec §6.4 deliverable 2 ("dragging a task card onto an open note")
/// against §6.1's single-active-tab layout (`RootView.expandedBody`'s
/// `switch model.selection` mounts exactly one tab's content at a time):
/// there is no way to already be looking at a note while dragging from the
/// Tasks board, since starting that drag requires being on the Tasks tab.
/// `.onDrop(isTargeted:)` below turns hovering a drag over this button into
/// a tab switch, mirroring Finder's spring-loaded folders, so the drag can
/// continue on into the now-visible note and land there — the drop itself
/// is still declined here (`{ _ in false }`), same as a release outside
/// every task-board group (spec §6.3a): only *dwelling* over the icon
/// switches tabs, not letting go on it.
///
/// Gated on `isDragging` (`PanelViewModel.isDragging`, the board's own
/// `NSEvent.pressedMouseButtons` poll — untouched by any of this) so an
/// unrelated plain-text drag from outside the app can't reroute the panel's
/// own navigation, and on `!isSelected` so hovering the already-active tab
/// is a no-op rather than a redundant reselect.
private struct TabRailButton: View {
    let tab: AppTab
    let isSelected: Bool
    let isCompact: Bool
    let isDragging: Bool
    let action: () -> Void

    @State private var isDropTargeted = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 16, weight: .medium))
                if !isCompact {
                    Text(tab.title)
                        .font(.system(size: 9))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Tokens.Space.sm)
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            .background(
                RoundedRectangle(cornerRadius: Tokens.Radius.sm)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : .clear)
            )
            // Without this, SwiftUI only hit-tests the glyph and label text
            // themselves, not the padding or the `maxWidth: .infinity`
            // expanse around them — so most of what visually reads as the
            // button (user report: "need to click a few times or somehow
            // click not work") silently swallows taps. This makes the whole
            // frame, background included, respond.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Tokens.Space.xs)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .onDrop(of: [.plainText], isTargeted: $isDropTargeted) { _ in false }
        .onChange(of: isDropTargeted) { _, isTargeted in
            guard isTargeted, isDragging, !isSelected else { return }
            action()
        }
    }
}
