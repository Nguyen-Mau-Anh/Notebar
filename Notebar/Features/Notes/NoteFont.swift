import AppKit

/// The concrete `NSFont`s and paragraph styles behind spec §6.2/§6.2b's type
/// scale (`Tokens.Typography`). Centralized here so `NoteEditorView` (initial
/// typing attributes), `NoteTextStyling` (toggling a style), and
/// `NoteMarkdownShortcuts` (starting a list) all build the exact same fonts
/// rather than each constructing a slightly different copy that would make
/// `NoteTextStyling.activeStyles`'s point-size comparison unreliable.
enum NoteFont {
    static let body = NSFont.systemFont(ofSize: Tokens.Typography.bodySize)
    static let heading1 = NSFont.systemFont(ofSize: Tokens.Typography.heading1Size, weight: .semibold)
    static let heading2 = NSFont.systemFont(ofSize: Tokens.Typography.heading2Size, weight: .semibold)
    static let code = NSFont.monospacedSystemFont(ofSize: Tokens.Typography.codeSize, weight: .regular)

    static func paragraphStyle(lineHeight: CGFloat) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = lineHeight
        style.maximumLineHeight = lineHeight
        return style
    }

    static var bodyParagraphStyle: NSMutableParagraphStyle {
        paragraphStyle(lineHeight: Tokens.Typography.bodyLineHeight)
    }

    /// What a brand-new, still-empty note's `NSTextView` starts with, so the
    /// very first character typed already carries body size and line height
    /// rather than whatever `NSTextView`'s own built-in default is.
    ///
    /// `.foregroundColor: .labelColor` matches `NoteEditorView`'s own
    /// `textView.textColor` — a dynamic system colour, not hardcoded black —
    /// so a freshly typed character stays readable if the appearance flips
    /// mid-edit rather than waiting on `textColor` alone to cover it.
    static var typingAttributes: [NSAttributedString.Key: Any] {
        [.font: body, .paragraphStyle: bodyParagraphStyle, .foregroundColor: NSColor.labelColor]
    }
}
