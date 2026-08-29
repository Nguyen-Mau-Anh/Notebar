import Foundation
import Testing
import GRDB
@testable import NotebarCore
@testable import NotebarStore

/// Every test opens its own in-memory database — fast, and isolated from
/// every other test, so ordering never matters.
private func makeRepository() throws -> GRDBNoteRepository {
    let dbQueue = try DatabaseQueue()
    try Migrations.migrator.migrate(dbQueue)
    return GRDBNoteRepository(dbQueue: dbQueue)
}

@Suite("GRDBNoteRepository CRUD")
struct GRDBNoteRepositoryCRUDTests {
    @Test("a created note round-trips through all()")
    func createThenRead() throws {
        let repository = try makeRepository()
        let created = try repository.create()

        let all = try repository.all()
        #expect(all.count == 1)
        #expect(all.first?.id == created.id)
        #expect(all.first?.body == "")
    }

    @Test("update persists new field values")
    func update() throws {
        let repository = try makeRepository()
        var note = try repository.create()
        note.body = "Buy milk"
        note.isPinned = true

        try repository.update(note)

        let reloaded = try repository.all().first { $0.id == note.id }
        #expect(reloaded?.body == "Buy milk")
        #expect(reloaded?.isPinned == true)
    }

    @Test("update stamps updatedAt forward")
    func updateStampsUpdatedAt() throws {
        let repository = try makeRepository()
        var note = try repository.create()
        let originalUpdatedAt = note.updatedAt

        // Guarantee a measurable gap regardless of clock resolution.
        Thread.sleep(forTimeInterval: 0.01)
        note.body = "changed"
        try repository.update(note)

        let reloaded = try repository.all().first { $0.id == note.id }
        #expect((reloaded?.updatedAt ?? .distantPast) > originalUpdatedAt)
    }

    @Test("renaming a note persists the new title and does not change the body")
    func renameTitleLeavesBodyUntouched() throws {
        let repository = try makeRepository()
        var note = try repository.create()
        note.body = "Some body text"
        try repository.update(note)

        note.title = "My Renamed Note"
        try repository.update(note)

        let reloaded = try repository.all().first { $0.id == note.id }
        #expect(reloaded?.title == "My Renamed Note")
        #expect(reloaded?.body == "Some body text")
    }

    @Test("update on an unknown id throws")
    func updateUnknownID() throws {
        let repository = try makeRepository()
        let ghost = Note(id: "missing", sortOrder: 0)
        #expect(throws: (any Error).self) {
            try repository.update(ghost)
        }
    }

    @Test("delete removes the note")
    func delete() throws {
        let repository = try makeRepository()
        let note = try repository.create()

        try repository.delete(id: note.id)

        #expect(try repository.all().isEmpty)
    }

    @Test("deleting an unknown id is a no-op")
    func deleteUnknownID() throws {
        let repository = try makeRepository()
        _ = try repository.create()

        try repository.delete(id: "not-a-real-id")

        #expect(try repository.all().count == 1)
    }
}

@Suite("closing a tab is not deleting a note")
struct GRDBNoteRepositoryOpenTabTests {
    /// The invariant the All-notes menu (spec §6.2a) rests on: removing a
    /// note's `open_tab` row — what closing a tab actually does — must not
    /// touch the `note` row. If it did, there would be nothing left for the
    /// menu to list back into the strip.
    @Test("a note whose tab has been closed still appears in all()")
    func noteSurvivesTabClose() throws {
        let dbQueue = try DatabaseQueue()
        try Migrations.migrator.migrate(dbQueue)
        let notes = GRDBNoteRepository(dbQueue: dbQueue)
        let openTabs = GRDBOpenTabRepository(dbQueue: dbQueue)

        let note = try notes.create()
        try openTabs.replaceAll([
            OpenTab(kind: OpenTab.noteKind, refID: note.id, sortOrder: 0, isActive: true)
        ])

        // "Closing the tab": the open-tab set is replaced without this
        // note's entry, exactly what `PanelViewModel.removeTab` triggers.
        try openTabs.replaceAll([])

        #expect(try openTabs.all().isEmpty)
        #expect(try notes.all().contains { $0.id == note.id })
    }
}

@Suite("body_plain stays in sync with body")
struct GRDBNoteRepositoryBodyPlainTests {
    @Test("body_plain matches body immediately after create")
    func afterCreate() throws {
        let dbQueue = try DatabaseQueue()
        try Migrations.migrator.migrate(dbQueue)
        let repository = GRDBNoteRepository(dbQueue: dbQueue)

        let note = try repository.create()

        let bodyPlain = try dbQueue.read { db in
            try String.fetchOne(db, sql: "SELECT body_plain FROM note WHERE id = ?", arguments: [note.id])
        }
        #expect(bodyPlain == note.body)
    }

    @Test("body_plain matches body after an update, in the same row write")
    func afterUpdate() throws {
        let dbQueue = try DatabaseQueue()
        try Migrations.migrator.migrate(dbQueue)
        let repository = GRDBNoteRepository(dbQueue: dbQueue)

        var note = try repository.create()
        note.body = "Remember to feed the cat"
        try repository.update(note)

        let bodyPlain = try dbQueue.read { db in
            try String.fetchOne(db, sql: "SELECT body_plain FROM note WHERE id = ?", arguments: [note.id])
        }
        #expect(bodyPlain == "Remember to feed the cat")
    }
}

@Suite("FTS search")
struct GRDBNoteRepositorySearchTests {
    @Test("finds a note by a word in its body")
    func findsByBodyWord() throws {
        let repository = try makeRepository()
        var note = try repository.create()
        note.body = "Remember to buy oat milk tomorrow"
        try repository.update(note)

        let results = try repository.search("oat")

        #expect(results.contains { $0.id == note.id })
    }

    @Test("does not find a deleted note")
    func excludesDeleted() throws {
        let repository = try makeRepository()
        var note = try repository.create()
        note.body = "Remember to buy oat milk tomorrow"
        try repository.update(note)
        try repository.delete(id: note.id)

        let results = try repository.search("oat")

        #expect(results.isEmpty)
    }

    @Test("deleting a note removes it from all() and drops it from FTS, by title or body")
    func deleteRemovesFromSearchIndex() throws {
        let repository = try makeRepository()
        var note = try repository.create()
        note.title = "Grocery List"
        note.body = "Remember to buy oat milk"
        try repository.update(note)

        try repository.delete(id: note.id)

        #expect(try repository.all().isEmpty)
        #expect(try repository.search("Grocery").isEmpty)
        #expect(try repository.search("oat").isEmpty)
    }

    @Test("a blank query returns no results")
    func blankQuery() throws {
        let repository = try makeRepository()
        var note = try repository.create()
        note.body = "anything"
        try repository.update(note)

        #expect(try repository.search("   ").isEmpty)
    }
}

@Suite("fractional sortOrder")
struct GRDBNoteRepositorySortOrderTests {
    @Test("inserting between two notes yields a value strictly between them")
    func reorderBetween() throws {
        let repository = try makeRepository()
        let first = try repository.create()
        let second = try repository.create()
        #expect(first.sortOrder < second.sortOrder)

        let third = try repository.create()
        let moved = try repository.reorder(id: third.id, before: first.id, after: second.id)

        #expect(moved.sortOrder > first.sortOrder)
        #expect(moved.sortOrder < second.sortOrder)
    }

    @Test("reordering to the very start moves before every existing note")
    func reorderToStart() throws {
        let repository = try makeRepository()
        let first = try repository.create()
        let second = try repository.create()

        let moved = try repository.reorder(id: second.id, before: nil, after: first.id)

        #expect(moved.sortOrder < first.sortOrder)
    }

    @Test("reordering to the very end moves past every existing note")
    func reorderToEnd() throws {
        let repository = try makeRepository()
        let first = try repository.create()
        let second = try repository.create()

        let moved = try repository.reorder(id: first.id, before: second.id, after: nil)

        #expect(moved.sortOrder > second.sortOrder)
    }
}
