import Foundation
import Testing
import GRDB
@testable import NotebarCore
@testable import NotebarStore

/// Every test opens its own in-memory database — see `GRDBNoteRepositoryTests`
/// for why.
private func makeRepositories() throws -> (links: GRDBLinkRepository, notes: GRDBNoteRepository, tasks: GRDBTaskRepository) {
    let dbQueue = try DatabaseQueue()
    try Migrations.migrator.migrate(dbQueue)
    return (
        GRDBLinkRepository(dbQueue: dbQueue),
        GRDBNoteRepository(dbQueue: dbQueue),
        GRDBTaskRepository(dbQueue: dbQueue)
    )
}

@Suite("GRDBLinkRepository")
struct GRDBLinkRepositoryTests {
    @Test("a created link is found by outgoing(from:) and incoming(to:) from either side")
    func roundTrip() throws {
        let (links, notes, tasks) = try makeRepositories()
        let note = try notes.create()
        let columnID = try tasks.columns()[0].id
        let task = try tasks.create(title: "Ship it", columnID: columnID)

        let link = Link(srcType: .note, srcId: note.id, dstType: .task, dstId: task.id)
        try links.create(link)

        let outgoing = try links.outgoing(from: LinkTarget(type: .note, id: note.id))
        #expect(outgoing.count == 1)
        #expect(outgoing.first?.dstId == task.id)
        #expect(outgoing.first?.dstType == .task)

        let incoming = try links.incoming(to: LinkTarget(type: .task, id: task.id))
        #expect(incoming.count == 1)
        #expect(incoming.first?.srcId == note.id)
        #expect(incoming.first?.srcType == .note)

        // The other direction should each be empty: nothing points *into*
        // the note, and the task has no outgoing links of its own.
        #expect(try links.incoming(to: LinkTarget(type: .note, id: note.id)).isEmpty)
        #expect(try links.outgoing(from: LinkTarget(type: .task, id: task.id)).isEmpty)
    }

    @Test("incoming(to:) returns links from both a note and a task pointing at one target")
    func incomingFromBothEntityTypes() throws {
        let (links, notes, tasks) = try makeRepositories()
        let sourceNote = try notes.create()
        let columnID = try tasks.columns()[0].id
        let sourceTask = try tasks.create(title: "Ship it", columnID: columnID)
        let target = try notes.create()

        try links.create(Link(srcType: .note, srcId: sourceNote.id, dstType: .note, dstId: target.id))
        try links.create(Link(srcType: .task, srcId: sourceTask.id, dstType: .note, dstId: target.id))

        let incoming = try links.incoming(to: LinkTarget(type: .note, id: target.id))
        #expect(incoming.count == 2)
        #expect(Set(incoming.map(\.srcType)) == [.note, .task])
        #expect(Set(incoming.map(\.srcId)) == [sourceNote.id, sourceTask.id])
    }

    @Test("deleting a chip's target leaves the referencing note's stored text untouched")
    func deletingTargetPreservesReferencingNoteText() throws {
        let (links, notes, _) = try makeRepositories()
        let note = try notes.create()
        let target = try notes.create()

        let chipText = "See @Other "
        let bodyRTF = NoteRTF.rtfdData(from: NSAttributedString(string: chipText))
        let link = Link(srcType: .note, srcId: note.id, dstType: .note, dstId: target.id)
        try links.create(link, savingNoteBody: note.id, bodyRTF: bodyRTF, bodyPlain: chipText)

        // Deleting the target cascades the `link` row away (`LinkSchema`'s
        // `AFTER DELETE` trigger) — that must never touch the referencing
        // note's own row. A tombstone is the chip's *styling* changing, not
        // its text (spec §6.4: "never delete the user's text").
        try notes.delete(id: target.id)

        let reloadedNote = try notes.fetch(id: note.id)
        #expect(reloadedNote?.bodyPlain == chipText)
        #expect(reloadedNote?.bodyRTF == bodyRTF)
        #expect(try links.incoming(to: LinkTarget(type: .note, id: target.id)).isEmpty)
    }

    @Test("the UNIQUE constraint rejects a duplicate link")
    func duplicateRejected() throws {
        let (links, notes, tasks) = try makeRepositories()
        let noteA = try notes.create()
        let noteB = try notes.create()
        _ = noteB
        let columnID = try tasks.columns()[0].id
        let task = try tasks.create(title: "Ship it", columnID: columnID)

        let link = Link(srcType: .note, srcId: noteA.id, dstType: .task, dstId: task.id)
        try links.create(link)

        // Same (src_type, src_id, dst_type, dst_id, kind) tuple, fresh id —
        // the `id` primary key differs, so only the `UNIQUE` constraint on
        // the four-plus-kind tuple can be what rejects this.
        let duplicate = Link(srcType: .note, srcId: noteA.id, dstType: .task, dstId: task.id)
        #expect(throws: (any Error).self) {
            try links.create(duplicate)
        }
    }

    @Test("create(_:savingNoteBody:bodyRTF:bodyPlain:) writes the link and the note body in one call")
    func createWithNoteBody() throws {
        let (links, notes, _) = try makeRepositories()
        let note = try notes.create()
        let target = try notes.create()

        let link = Link(srcType: .note, srcId: note.id, dstType: .note, dstId: target.id)
        let bodyRTF = NoteRTF.rtfdData(from: NSAttributedString(string: "See @Other"))
        try links.create(link, savingNoteBody: note.id, bodyRTF: bodyRTF, bodyPlain: "See @Other")

        let reloadedNote = try notes.fetch(id: note.id)
        #expect(reloadedNote?.bodyPlain == "See @Other")

        let outgoing = try links.outgoing(from: LinkTarget(type: .note, id: note.id))
        #expect(outgoing.count == 1)
        #expect(outgoing.first?.dstId == target.id)
    }

    @Test("create(_:savingNoteBody:bodyRTF:bodyPlain:) throws for an unknown note id, and inserts nothing")
    func createWithNoteBodyUnknownNote() throws {
        let (links, notes, _) = try makeRepositories()
        let target = try notes.create()
        let link = Link(srcType: .note, srcId: "missing-note", dstType: .note, dstId: target.id)

        #expect(throws: (any Error).self) {
            try links.create(link, savingNoteBody: "missing-note", bodyRTF: Data(), bodyPlain: "")
        }

        // The failed note update must not have left the link behind —
        // both writes share one transaction (deliverable 3).
        #expect(try links.outgoing(from: LinkTarget(type: .note, id: "missing-note")).isEmpty)
    }

    @Test("deleting a note removes every link that touches it, on either end")
    func deletingNoteCascades() throws {
        let (links, notes, tasks) = try makeRepositories()
        let noteA = try notes.create()
        let noteB = try notes.create()
        let columnID = try tasks.columns()[0].id
        let task = try tasks.create(title: "Ship it", columnID: columnID)

        try links.create(Link(srcType: .note, srcId: noteA.id, dstType: .task, dstId: task.id))
        try links.create(Link(srcType: .note, srcId: noteB.id, dstType: .note, dstId: noteA.id))

        try notes.delete(id: noteA.id)

        // noteA -> task (noteA as source) and noteB -> noteA (noteA as
        // destination) must both be gone.
        #expect(try links.outgoing(from: LinkTarget(type: .note, id: noteA.id)).isEmpty)
        #expect(try links.incoming(to: LinkTarget(type: .note, id: noteA.id)).isEmpty)
        // The unrelated link's other endpoint is untouched.
        #expect(try links.outgoing(from: LinkTarget(type: .note, id: noteB.id)).isEmpty)
    }

    @Test("deleting a task removes every link that touches it, on either end")
    func deletingTaskCascades() throws {
        let (links, notes, tasks) = try makeRepositories()
        let note = try notes.create()
        let columnID = try tasks.columns()[0].id
        let task = try tasks.create(title: "Ship it", columnID: columnID)

        try links.create(Link(srcType: .note, srcId: note.id, dstType: .task, dstId: task.id))

        try tasks.delete(id: task.id)

        #expect(try links.incoming(to: LinkTarget(type: .task, id: task.id)).isEmpty)
        #expect(try links.outgoing(from: LinkTarget(type: .note, id: note.id)).isEmpty)
    }

    @Test("delete(id:) removes a link by id and is a no-op for an unknown id")
    func deleteByID() throws {
        let (links, notes, tasks) = try makeRepositories()
        let note = try notes.create()
        let columnID = try tasks.columns()[0].id
        let task = try tasks.create(title: "Ship it", columnID: columnID)
        let link = try links.create(Link(srcType: .note, srcId: note.id, dstType: .task, dstId: task.id))

        try links.delete(id: link.id)
        #expect(try links.outgoing(from: LinkTarget(type: .note, id: note.id)).isEmpty)

        // No throw for an id that no longer (or never did) exist.
        try links.delete(id: link.id)
    }
}

@Suite("LinkURL")
struct LinkURLTests {
    @Test("a note URL parses back to the right type and id")
    func noteRoundTrip() throws {
        let url = LinkURL.url(for: .note, id: "abc-123")
        let target = LinkURL.parse(url)
        #expect(target?.type == .note)
        #expect(target?.id == "abc-123")
    }

    @Test("a task URL parses back to the right type and id")
    func taskRoundTrip() throws {
        let url = LinkURL.url(for: .task, id: "def-456")
        let target = LinkURL.parse(url)
        #expect(target?.type == .task)
        #expect(target?.id == "def-456")
    }

    @Test("a URL with a foreign scheme does not parse")
    func foreignScheme() throws {
        #expect(LinkURL.parse(URL(string: "https://example.com/note/abc")!) == nil)
    }

    @Test("a notebar URL with an unknown host does not parse")
    func unknownHost() throws {
        #expect(LinkURL.parse(URL(string: "notebar://board/abc")!) == nil)
    }
}
