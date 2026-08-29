import SwiftUI

struct TabRail: View {
    @Binding var selection: AppTab
    let isCompact: Bool

    var body: some View {
        VStack(spacing: Tokens.Space.xs) {
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
