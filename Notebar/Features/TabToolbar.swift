import SwiftUI

/// The 36pt toolbar row every content tab opens with (spec §6.4a): context
/// on the left, primary action on the right, a hairline beneath. The shape
/// is fixed across tabs so the primary action is always in the same place —
/// the user should never have to look for it.
struct TabToolbar<Left: View, Right: View>: View {
    @ViewBuilder let left: () -> Left
    @ViewBuilder let right: () -> Right

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Tokens.Space.sm) {
                left()
                Spacer(minLength: Tokens.Space.sm)
                right()
            }
            .padding(.horizontal, Tokens.Space.md)
            .frame(height: Tokens.Size.toolbarHeight)

            Divider()
        }
    }
}

/// The 28x28pt primary-action affordance on the toolbar's right side (`+`
/// for a new note or task). `.secondary`, stepping to `.accent` on hover
/// with a `radius.sm` background at 8% accent (spec §6.4a).
struct ToolbarActionButton: View {
    let symbol: String
    let accessibilityLabel: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundStyle(isHovering ? Color.accentColor : Color.secondary)
                .frame(width: Tokens.Size.actionHitTarget, height: Tokens.Size.actionHitTarget)
                .background(
                    RoundedRectangle(cornerRadius: Tokens.Radius.sm)
                        .fill(isHovering ? Color.accentColor.opacity(0.08) : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(accessibilityLabel)
    }
}
