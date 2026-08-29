import SwiftUI

struct TabRail: View {
    @Binding var selection: AppTab
    @Binding var isPinned: Bool
    @Binding var isMaximized: Bool
    let isCompact: Bool

    var body: some View {
        VStack(spacing: Tokens.Space.xs) {
            ControlRow(isPinned: $isPinned, isMaximized: $isMaximized)

            Divider()

            ForEach(AppTab.allCases) { tab in
                TabRailButton(
                    tab: tab,
                    isSelected: selection == tab,
                    isCompact: isCompact
                ) {
                    selection = tab
                }
            }
            Spacer()
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
        .frame(width: Tokens.Size.railWidth, height: Tokens.Size.pinHeight)
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
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isMaximized ? "Restore panel size" : "Maximize panel")
        .accessibilityAddTraits(isMaximized ? [.isSelected] : [])
    }
}

private struct TabRailButton: View {
    let tab: AppTab
    let isSelected: Bool
    let isCompact: Bool
    let action: () -> Void

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
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Tokens.Space.xs)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
