import Foundation

/// Storage for `Link` (spec §5's `link` table), defined here so
/// `NotebarStore`'s GRDB implementation has a contract to satisfy without
/// this module ever importing GRDB — see `NoteRepository`'s doc comment for
/// the full reasoning, which applies unchanged here.
public protocol LinkRepository {
    /// Creates a link and persists it immediately.
    @discardableResult
    func create(_ link: Link) throws -> Link

    /// Inserts `link` and saves `noteID`'s body in the same SQLite
    /// transaction (spec §6.4 deliverable 3): the one write path chip
    /// insertion goes through, so a chip's attributed run and the `link` row
    /// behind it are always committed together — a crash between the two
    /// can never leave one without the other. `noteID` is always the note
    /// being edited (the `@` autocomplete only exists in a note body), i.e.
    /// `link.srcType == .note && link.srcId == noteID`; the destination can
    /// be either a note or a task. The row must already exist; unknown ids
    /// throw.
    @discardableResult
    func create(_ link: Link, savingNoteBody noteID: String, bodyRTF: Data, bodyPlain: String) throws -> Link

    /// Deletes a link. A no-op if `id` does not exist.
    func delete(id: Link.ID) throws

    /// Every link whose source is `target`, i.e. every outbound reference
    /// from that note/task — what `idx_link_src` exists to serve.
    func outgoing(from target: LinkTarget) throws -> [Link]

    /// Every link whose destination is `target`, i.e. every inbound
    /// reference to that note/task — what `idx_link_dst` exists to serve
    /// (spec §5's "backlinks" comment on that index). Nothing reads this yet
    /// this task; it's here so the next one (backlinks) needs no protocol
    /// change to use it.
    func incoming(to target: LinkTarget) throws -> [Link]
}
