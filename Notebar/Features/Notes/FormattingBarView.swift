import SwiftUI

/// Spec §6.2b: a 32pt row directly beneath the tab toolbar, with a hairline
/// beneath it, holding the seven formatting controls in `NoteTextStyle`.
/// Visible only while a note is open — `NotesTab`'s `NoteEditorContainer` is
/// what actually conditions its presence on that; this view always draws the
/// full bar whenever it's placed.
struct FormattingBarView: View {
    let context: NoteEditingContext

    var body: some View {
        VStack(spacing: 0) {
            // Below the compact breakpoint the bar scrolls horizontally
            // instead of wrapping to a second row (spec §6.2b): a fixed
            // height on the `ScrollView` itself, not just its content, is
            // what keeps the chrome from growing taller as the panel
            // narrows.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Tokens.Space.xs) {
                    ForEach(NoteTextStyle.allCases, id: \.self) { style in
                        FormattingBarButton(
                            style: style,
                            isActive: context.activeStyles.contains(style),
                            action: { context.toggle(style) }
                        )
                    }
                }
                .padding(.horizontal, Tokens.Space.sm)
            }
            .frame(height: Tokens.Size.formattingBarHeight)

            Divider()
        }
    }
}

/// One 28x28pt control: `.secondary` normally, `.accent` when the caret sits
/// inside that style (spec §6.2b).
private struct FormattingBarButton: View {
    let style: NoteTextStyle
    let isActive: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: style.symbol)
                .font(.system(size: 15))
                .foregroundStyle(isActive || isHovering ? Color.accentColor : Color.secondary)
                .frame(width: Tokens.Size.formattingBarButtonSize, height: Tokens.Size.formattingBarButtonSize)
                .background(
                    RoundedRectangle(cornerRadius: Tokens.Radius.sm)
                        .fill(isActive ? Color.accentColor.opacity(0.12) : (isHovering ? Color.accentColor.opacity(0.08) : .clear))
                )
                // SwiftUI hit-tests only drawn content; without this a
                // transparent-background button only responds to clicks on
                // its glyph, not its full 28x28pt target (a real bug this
                // project already hit once).
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(KeyEquivalent(style.keyEquivalent.key), modifiers: style.keyEquivalent.modifiers)
        .onHover { isHovering = $0 }
        .accessibilityLabel(style.accessibilityLabel)
    }
}
