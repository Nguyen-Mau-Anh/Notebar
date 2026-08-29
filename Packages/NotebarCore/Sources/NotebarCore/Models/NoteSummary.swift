import Foundation

/// The lightweight projection of a note the all-notes menu actually needs
/// (spec §6.2c deliverable 4): just enough to render a title and a relative
/// timestamp, from `NoteRepository.summaries()`.
///
/// Deliberately its own type rather than a `Note` with an empty/placeholder
/// body: `summaries()` never selects `body_rtf` off disk in the first place
/// — that's the whole point once bodies can hold embedded images, twenty
/// notes with one screenshot each would otherwise mean reading tens of
/// megabytes just to draw a list of names — and giving that result a
/// distinct type is what keeps the type system honest about it. A `Note`
/// with `bodyRTF: Data()` would compile at every call site whether or not
/// the body was actually loaded; `NoteSummary` has no `bodyRTF` field at
/// all, so nothing can accidentally reach for a body that was never read.
public struct NoteSummary: Identifiable, Equatable, Sendable {
    public var id: Note.ID
    public var title: String
    public var updatedAt: Date

    public init(id: Note.ID, title: String, updatedAt: Date) {
        self.id = id
        self.title = title
        self.updatedAt = updatedAt
    }
}

public extension NoteSummary {
    /// Mirrors `Note.displayTitle` exactly — the all-notes menu must show
    /// "Untitled" the same way the tab strip does.
    var displayTitle: String {
        title.isEmpty ? "Untitled" : title
    }
}
