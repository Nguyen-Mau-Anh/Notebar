import AppKit

/// The formatting operations behind spec §6.2b's bar and deliverable 3's
/// markdown shortcuts — a namespace of functions over `NSTextView` rather
/// than methods on a subclass, so a toolbar click (`NoteEditingContext`) and
/// a markdown trigger (`NoteMarkdownShortcuts`) share exactly one
/// implementation of, say, "turn this paragraph into a bulleted list"
/// instead of two copies that could drift apart.
///
/// Every function here mutates `textStorage` directly rather than going
/// through the text view's own editing selectors — the only way to apply an
/// attribute to an existing range without also replacing its characters.
/// That bypasses the normal edit path AppKit uses to post its "text changed"
/// notification, so every caller must follow up with `textView.didChangeText()`
/// itself; `NoteEditingContext.toggle` and `NoteMarkdownShortcuts.handle` both
/// do.
enum NoteTextStyling {
    /// What the bar reflects and `⌘B`/`⌘I`/etc. toggle: the style(s) that
    /// apply at the caret, or starting at the selection. Character styles
    /// (bold/italic/code) read the font at the selection's start, matching
    /// what `NSTextView.typingAttributes` itself tracks for an empty
    /// selection; paragraph styles (heading/list) read the paragraph the
    /// selection starts in.
    static func activeStyles(in textView: NSTextView) -> Set<NoteTextStyle> {
        let selectedRange = textView.selectedRange()
        let font = currentFont(in: textView, at: selectedRange)
        let paragraphStyle = currentParagraphStyle(in: textView, at: selectedRange)
        let manager = NSFontManager.shared

        var styles: Set<NoteTextStyle> = []
        if manager.traits(of: font).contains(.boldFontMask) { styles.insert(.bold) }
        if manager.traits(of: font).contains(.italicFontMask) { styles.insert(.italic) }
        if isCodeFont(font) { styles.insert(.code) }
        if isHeadingFont(font, level: 1) { styles.insert(.heading1) }
        if isHeadingFont(font, level: 2) { styles.insert(.heading2) }
        if let markerFormat = paragraphStyle?.textLists.first?.markerFormat {
            switch markerFormat {
            case .decimal: styles.insert(.numberedList)
            case .check: styles.insert(.checklist)
            default: styles.insert(.bulletedList)
            }
        }
        return styles
    }

    static func toggleBold(in textView: NSTextView) {
        toggleTrait(.boldFontMask, in: textView)
    }

    static func toggleItalic(in textView: NSTextView) {
        toggleTrait(.italicFontMask, in: textView)
    }

    /// A character-level attribute, like bold/italic, not a paragraph-level
    /// one like the headings below — "Inline code" (spec §6.2b) is meant to
    /// mark a run of text within an ordinary paragraph, not a whole block.
    static func toggleCode(in textView: NSTextView) {
        let alreadyCode = activeStyles(in: textView).contains(.code)
        setFont(alreadyCode ? NoteFont.body : NoteFont.code, in: textView, wholeParagraph: false)
    }

    /// Headings are whole-paragraph font changes, unlike bold/italic/code:
    /// selecting a heading level applies to every character in the current
    /// paragraph, overriding any bold/italic within it — a deliberate
    /// simplification, matching how heading styles behave in most rich-text
    /// editors.
    static func toggleHeading(_ level: Int, in textView: NSTextView) {
        let style: NoteTextStyle = level == 1 ? .heading1 : .heading2
        let alreadyHeading = activeStyles(in: textView).contains(style)
        let font = alreadyHeading ? NoteFont.body : (level == 1 ? NoteFont.heading1 : NoteFont.heading2)
        let lineHeight = alreadyHeading
            ? Tokens.Typography.bodyLineHeight
            : (level == 1 ? Tokens.Typography.heading1LineHeight : Tokens.Typography.heading2LineHeight)

        setFont(font, in: textView, wholeParagraph: true)
        applyParagraphStyle(NoteFont.paragraphStyle(lineHeight: lineHeight), in: textView, preservingTextLists: true)
    }

    static func toggleList(ordered: Bool, in textView: NSTextView) {
        applyListToggle(
            style: ordered ? .numberedList : .bulletedList,
            markerFormat: ordered ? .decimal : .disc,
            renumbers: ordered,
            in: textView
        )
    }

    /// A checklist (spec §6.2b) is a list whose marker is a checkbox glyph
    /// rather than a bullet or number — the same text-level bookkeeping as
    /// `toggleList` above, just with `.check` as the tag `activeStyles` and
    /// `NoteListEditing.handleChecklistClick` use to recognize a checklist
    /// paragraph. `.check` is never used for its own built-in glyph
    /// (`NSTextList.marker(forItemNumber:)` would return "✓", a constant
    /// checkmark unrelated to checked/unchecked state); `NoteListMarkers.markerText`
    /// special-cases `.check` to always produce the unchecked glyph instead,
    /// since toggle state isn't something a *new* item ever starts other
    /// than unchecked.
    static func toggleChecklist(in textView: NSTextView) {
        applyListToggle(style: .checklist, markerFormat: .check, renumbers: false, in: textView)
    }

    /// Shared by `toggleList` and `toggleChecklist`: apply or remove
    /// whichever list style `style`/`markerFormat` describes. Checklists
    /// never renumber (`renumbers: false`) the same way bulleted lists
    /// don't — neither marker depends on item position.
    private static func applyListToggle(
        style: NoteTextStyle,
        markerFormat: NSTextList.MarkerFormat,
        renumbers: Bool,
        in textView: NSTextView
    ) {
        let alreadyThisList = activeStyles(in: textView).contains(style)
        let existing = currentParagraphStyle(in: textView, at: textView.selectedRange())
        let newStyle = (existing?.mutableCopy() as? NSMutableParagraphStyle) ?? NoteFont.bodyParagraphStyle

        if alreadyThisList {
            // Strip the markers this list inserted *before* the style below
            // clears `textLists` — `NoteListEditing.stripMarkers` needs the
            // still-current style to know which paragraphs have one.
            NoteListEditing.stripMarkers(in: textView)
            newStyle.textLists = []
            newStyle.headIndent = 0
            newStyle.firstLineHeadIndent = 0
            applyParagraphStyle(newStyle, in: textView, preservingTextLists: false)
        } else {
            newStyle.textLists = [NSTextList(markerFormat: markerFormat, options: 0)]
            newStyle.headIndent = Tokens.Typography.listIndent
            newStyle.firstLineHeadIndent = Tokens.Typography.listMarkerIndent
            applyParagraphStyle(newStyle, in: textView, preservingTextLists: false)
            // Spec §6.2d: TextKit renders no marker from `NSTextList` alone,
            // so on an empty line — including an entirely empty note —
            // applying a list above would look like nothing happened
            // without this inserting the marker as real text.
            NoteListEditing.insertMarkers(in: textView, ordered: renumbers)
        }
    }

    // MARK: - Character-level: bold/italic

    private static func toggleTrait(_ trait: NSFontTraitMask, in textView: NSTextView) {
        let manager = NSFontManager.shared
        let selectedRange = textView.selectedRange()

        guard let textStorage = textView.textStorage, selectedRange.length > 0 else {
            let font = currentFont(in: textView, at: selectedRange)
            let hasTrait = manager.traits(of: font).contains(trait)
            textView.typingAttributes[.font] = hasTrait
                ? manager.convert(font, toNotHaveTrait: trait)
                : manager.convert(font, toHaveTrait: trait)
            return
        }

        // Mirrors the standard "bold the whole selection unless it's
        // already uniformly bold, in which case un-bold it" rule: a mixed
        // selection is treated as "not yet styled" and gains the trait.
        var isFullyStyled = true
        textStorage.enumerateAttribute(.font, in: selectedRange) { value, _, stop in
            let font = (value as? NSFont) ?? NoteFont.body
            if !manager.traits(of: font).contains(trait) {
                isFullyStyled = false
                stop.pointee = true
            }
        }

        textStorage.beginEditing()
        textStorage.enumerateAttribute(.font, in: selectedRange) { value, range, _ in
            let font = (value as? NSFont) ?? NoteFont.body
            let newFont = isFullyStyled
                ? manager.convert(font, toNotHaveTrait: trait)
                : manager.convert(font, toHaveTrait: trait)
            textStorage.addAttribute(.font, value: newFont, range: range)
        }
        textStorage.endEditing()
    }

    // MARK: - Shared helpers

    private static func setFont(_ font: NSFont, in textView: NSTextView, wholeParagraph: Bool) {
        textView.typingAttributes[.font] = font
        guard let textStorage = textView.textStorage, textStorage.length > 0 else { return }
        let nsString = textStorage.string as NSString
        let selectedRange = textView.selectedRange()
        let range = wholeParagraph ? nsString.paragraphRange(for: selectedRange) : selectedRange
        guard range.length > 0 else { return }
        textStorage.beginEditing()
        textStorage.addAttribute(.font, value: font, range: range)
        textStorage.endEditing()
    }

    /// Applies a paragraph style to the current paragraph (and updates
    /// `typingAttributes` so it also governs whatever is typed next).
    /// `preservingTextLists` is true for the heading toggle, which must
    /// leave an in-progress list alone rather than clearing it — heading and
    /// list are independent axes, unlike list-vs-list in `toggleList`, which
    /// always replaces `textLists` outright.
    private static func applyParagraphStyle(
        _ style: NSMutableParagraphStyle,
        in textView: NSTextView,
        preservingTextLists: Bool
    ) {
        if preservingTextLists, let existingLists = currentParagraphStyle(in: textView, at: textView.selectedRange())?.textLists,
           !existingLists.isEmpty {
            style.textLists = existingLists
        }
        textView.typingAttributes[.paragraphStyle] = style
        guard let textStorage = textView.textStorage, textStorage.length > 0 else { return }
        let nsString = textStorage.string as NSString
        let paragraphRange = nsString.paragraphRange(for: textView.selectedRange())
        guard paragraphRange.length > 0 else { return }
        textStorage.beginEditing()
        textStorage.addAttribute(.paragraphStyle, value: style, range: paragraphRange)
        textStorage.endEditing()
    }

    private static func currentFont(in textView: NSTextView, at range: NSRange) -> NSFont {
        guard let textStorage = textView.textStorage, textStorage.length > 0 else {
            return (textView.typingAttributes[.font] as? NSFont) ?? NoteFont.body
        }
        let clampedLocation = min(range.location, textStorage.length - 1)
        return (textStorage.attribute(.font, at: clampedLocation, effectiveRange: nil) as? NSFont) ?? NoteFont.body
    }

    private static func currentParagraphStyle(in textView: NSTextView, at range: NSRange) -> NSParagraphStyle? {
        guard let textStorage = textView.textStorage, textStorage.length > 0 else {
            return textView.typingAttributes[.paragraphStyle] as? NSParagraphStyle
        }
        let nsString = textStorage.string as NSString
        let clampedLocation = min(range.location, textStorage.length - 1)
        let paragraphRange = nsString.paragraphRange(for: NSRange(location: clampedLocation, length: 0))
        guard paragraphRange.length > 0 else {
            return textView.typingAttributes[.paragraphStyle] as? NSParagraphStyle
        }
        return textStorage.attribute(.paragraphStyle, at: paragraphRange.location, effectiveRange: nil) as? NSParagraphStyle
    }

    /// Only `Tokens.Typography.codeSize` uses this exact point size, so a
    /// size match alone is a reliable-enough signal within this app's fixed
    /// four-size scale; `isFixedPitch` guards against a coincidence anyway.
    private static func isCodeFont(_ font: NSFont) -> Bool {
        abs(font.pointSize - Tokens.Typography.codeSize) < 0.5 && font.isFixedPitch
    }

    private static func isHeadingFont(_ font: NSFont, level: Int) -> Bool {
        let size = level == 1 ? Tokens.Typography.heading1Size : Tokens.Typography.heading2Size
        return abs(font.pointSize - size) < 0.5
    }
}
