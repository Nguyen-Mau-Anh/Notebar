import Foundation

/// A single note (spec §5's `note` table). Persisted through `NoteRepository`;
/// `NotebarStore` supplies the GRDB-backed implementation so this module
/// never has to import GRDB — see the architecture note on `NoteRepository`.
///
/// `body` is plain text for this milestone. Spec §5 ultimately wants an RTF
/// blob plus a derived `body_plain` shadow column once rich text lands; until
/// then `body` *is* the plain text, so the schema's `body` and `body_plain`
/// columns are identical. Keeping both columns now means the FTS5 setup
/// (`NoteSchema`) never has to be reworked — only how `body_plain` is derived
/// changes, not that it exists.
public struct Note: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var body: String
    public var createdAt: Date
    public var updatedAt: Date
    public var sortOrder: Double
    public var isPinned: Bool

    public init(
        id: String = UUID().uuidString,
        title: String = "Untitled",
        body: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        sortOrder: Double = 0,
        isPinned: Bool = false
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sortOrder = sortOrder
        self.isPinned = isPinned
    }
}

public extension Note {
    /// The tab strip's label. `title` is a stored, user-editable column —
    /// it no longer tracks `body` in any way, so typing in a note never
    /// changes its tab. New notes are created with `title == "Untitled"`
    /// and the rename UI itself refuses to commit a blank title, so `title`
    /// should never actually be empty; this stays defensive regardless.
    var displayTitle: String {
        title.isEmpty ? "Untitled" : title
    }
}
