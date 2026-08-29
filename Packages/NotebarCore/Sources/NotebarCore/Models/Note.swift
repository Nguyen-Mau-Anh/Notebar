import Foundation

/// A single note (spec §5's `note` table). Persisted through `NoteRepository`;
/// `NotebarStore` supplies the GRDB-backed implementation so this module
/// never has to import GRDB — see the architecture note on `NoteRepository`.
///
/// `bodyRTF` is the RTF blob `NSTextView` round-trips (spec §6.2); `bodyPlain`
/// is the plain-text shadow column FTS5 actually indexes, regenerated
/// alongside `bodyRTF` every time it changes so the two can never drift (spec
/// §5 "why RTF plus a plain shadow column"). Both live on `Note` itself,
/// rather than `bodyPlain` being something only `NotebarStore` derives,
/// because RTF decoding needs AppKit — a module this package must never
/// import (spec section 3, rule 1) — so nothing in `NotebarCore`, including
/// `isEmptyAndUntitled` below, can inspect `bodyRTF` directly. Whoever holds
/// the live `NSAttributedString` (the app target's note editor, or a
/// migration in `NotebarStore`) derives `bodyPlain` from it and sets both
/// fields together.
public struct Note: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var bodyRTF: Data
    public var bodyPlain: String
    public var createdAt: Date
    public var updatedAt: Date
    public var sortOrder: Double
    public var isPinned: Bool

    public init(
        id: String = UUID().uuidString,
        title: String = "Untitled",
        bodyRTF: Data = Data(),
        bodyPlain: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        sortOrder: Double = 0,
        isPinned: Bool = false
    ) {
        self.id = id
        self.title = title
        self.bodyRTF = bodyRTF
        self.bodyPlain = bodyPlain
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sortOrder = sortOrder
        self.isPinned = isPinned
    }
}

public extension Note {
    /// The tab strip's label. `title` is a stored, user-editable column —
    /// it no longer tracks the body in any way, so typing in a note never
    /// changes its tab. New notes are created with `title == "Untitled"`
    /// and the rename UI itself refuses to commit a blank title, so `title`
    /// should never actually be empty; this stays defensive regardless.
    var displayTitle: String {
        title.isEmpty ? "Untitled" : title
    }

    /// Whether the note is exactly as it was created: still titled
    /// "Untitled" and its body, once whitespace is stripped, empty. Such a
    /// note carries no information the user typed, so `PanelViewModel`
    /// deletes it outright when its tab is closed rather than leaving a
    /// contentless row to clutter the all-notes menu. A note with a title
    /// or a body is the user's actual content, and closing a tab must never
    /// destroy that.
    ///
    /// Checks `bodyPlain`, not `bodyRTF` — an "empty" `NSAttributedString`
    /// still serializes to a non-trivial RTF header, so `bodyRTF.isEmpty`
    /// would never be true for a real note and this predicate would stop
    /// working the moment rich text landed. `bodyPlain` is exactly the
    /// visible-text shadow that already answers "is there anything here."
    var isEmptyAndUntitled: Bool {
        displayTitle == "Untitled" && bodyPlain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
