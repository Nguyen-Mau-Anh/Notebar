import SwiftUI

struct TabRail: View {
    @Binding var selection: AppTab
    @Binding var isPinned: Bool
    let isCompact: Bool

    var body: some View {
        VStack(spacing: Tokens.Space.xs) {
            PinToggle(isPinned: $isPinned)

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

/// The 56x32pt pin toggle above the three tabs (spec §6.1). Deliberately
/// smaller and unlabelled so it does not read as a fourth tab — it changes
/// the panel's behaviour, not its content. Toggling it flows into
/// `PanelController.isPinned`, which `PanelMachine.shouldCollapse` already
/// treats as an absolute veto; this button is the only piece that was
/// missing.
private struct PinToggle: View {
    @Binding var isPinned: Bool

    var body: some View {
        Button {
            isPinned.toggle()
        } label: {
            Image(systemName: isPinned ? "pin.fill" : "pin")
                .font(.system(size: 15))
                .foregroundStyle(isPinned ? Color.accentColor : Color.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: Tokens.Size.pinHeight)
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
