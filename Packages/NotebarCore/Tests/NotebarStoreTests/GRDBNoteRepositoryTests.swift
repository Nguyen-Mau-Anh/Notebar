import AppKit
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

/// Builds an RTF blob the way the real note editor does — through `NoteRTF`
/// — from a plain string, for tests that don't care about attributes.
private func rtf(_ text: String) -> Data {
    NoteRTF.data(from: NSAttributedString(string: text))
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
        #expect(all.first?.bodyPlain == "")
    }

    @Test("update persists new field values")
    func update() throws {
        let repository = try makeRepository()
        var note = try repository.create()
        note.bodyRTF = rtf("Buy milk")
        note.bodyPlain = "Buy milk"
        note.isPinned = true

        try repository.update(note)

        let reloaded = try repository.all().first { $0.id == note.id }
        #expect(reloaded?.bodyPlain == "Buy milk")
        #expect(reloaded?.isPinned == true)
    }

    @Test("update stamps updatedAt forward")
    func updateStampsUpdatedAt() throws {
        let repository = try makeRepository()
        var note = try repository.create()
        let originalUpdatedAt = note.updatedAt

        // Guarantee a measurable gap regardless of clock resolution.
        Thread.sleep(forTimeInterval: 0.01)
        note.bodyRTF = rtf("changed")
        note.bodyPlain = "changed"
        try repository.update(note)

        let reloaded = try repository.all().first { $0.id == note.id }
        #expect((reloaded?.updatedAt ?? .distantPast) > originalUpdatedAt)
    }

    @Test("renaming a note persists the new title and does not change the body")
    func renameTitleLeavesBodyUntouched() throws {
        let repository = try makeRepository()
        var note = try repository.create()
        note.bodyRTF = rtf("Some body text")
        note.bodyPlain = "Some body text"
        try repository.update(note)

        note.title = "My Renamed Note"
        try repository.update(note)

        let reloaded = try repository.all().first { $0.id == note.id }
        #expect(reloaded?.title == "My Renamed Note")
        #expect(reloaded?.bodyPlain == "Some body text")
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

        // Given content, not left as the default "Untitled" + empty body:
        // `PanelViewModel.closeNote` deletes an untouched note outright
        // rather than merely closing its tab (see `Note.isEmptyAndUntitled`),
        // so a fixture note this test expects to survive closing must have
        // something in it — otherwise this test would no longer describe
        // what closing a tab actually does for a real note.
        var note = try notes.create()
        note.bodyRTF = rtf("Remember to feed the cat")
        note.bodyPlain = "Remember to feed the cat"
        try notes.update(note)
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

@Suite("body_plain stays in sync with body_rtf")
struct GRDBNoteRepositoryBodyPlainTests {
    @Test("body_plain matches bodyPlain immediately after create")
    func afterCreate() throws {
        let dbQueue = try DatabaseQueue()
        try Migrations.migrator.migrate(dbQueue)
        let repository = GRDBNoteRepository(dbQueue: dbQueue)

        let note = try repository.create()

        let bodyPlain = try dbQueue.read { db in
            try String.fetchOne(db, sql: "SELECT body_plain FROM note WHERE id = ?", arguments: [note.id])
        }
        #expect(bodyPlain == note.bodyPlain)
    }

    @Test("body_plain matches bodyPlain after an update, in the same row write")
    func afterUpdate() throws {
        let dbQueue = try DatabaseQueue()
        try Migrations.migrator.migrate(dbQueue)
        let repository = GRDBNoteRepository(dbQueue: dbQueue)

        var note = try repository.create()
        note.bodyRTF = rtf("Remember to feed the cat")
        note.bodyPlain = "Remember to feed the cat"
        try repository.update(note)

        let bodyPlain = try dbQueue.read { db in
            try String.fetchOne(db, sql: "SELECT body_plain FROM note WHERE id = ?", arguments: [note.id])
        }
        #expect(bodyPlain == "Remember to feed the cat")
    }

    @Test("body_plain derived from an RTF body matches its visible text")
    func bodyPlainMatchesRTFVisibleText() throws {
        let dbQueue = try DatabaseQueue()
        try Migrations.migrator.migrate(dbQueue)
        let repository = GRDBNoteRepository(dbQueue: dbQueue)

        var note = try repository.create()
        let attributed = NSMutableAttributedString(string: "Remember to buy oat milk")
        attributed.addAttribute(
            .font, value: NSFont.boldSystemFont(ofSize: 14),
            range: NSRange(location: 0, length: 8)
        )
        note.bodyRTF = NoteRTF.data(from: attributed)
        note.bodyPlain = NoteRTF.plainText(from: attributed)
        try repository.update(note)

        let reloaded = try repository.all().first { $0.id == note.id }
        let storedBodyPlain = try dbQueue.read { db in
            try String.fetchOne(db, sql: "SELECT body_plain FROM note WHERE id = ?", arguments: [note.id])
        }

        #expect(reloaded?.bodyPlain == "Remember to buy oat milk")
        #expect(storedBodyPlain == "Remember to buy oat milk")
        // The RTF blob itself still carries the bold attribute — only its
        // plain-text projection collapsed to bare characters.
        #expect(NoteRTF.plainText(fromRTF: reloaded?.bodyRTF ?? Data()) == "Remember to buy oat milk")
    }
}

@Suite("RTF round-trip")
struct GRDBNoteRepositoryRTFTests {
    @Test("a bold run survives a save and reload")
    func boldSurvivesRoundTrip() throws {
        let repository = try makeRepository()
        var note = try repository.create()

        let attributed = NSMutableAttributedString(string: "Buy milk")
        attributed.addAttribute(
            .font, value: NSFont.boldSystemFont(ofSize: 14),
            range: NSRange(location: 0, length: attributed.length)
        )
        note.bodyRTF = NoteRTF.data(from: attributed)
        note.bodyPlain = attributed.string
        try repository.update(note)

        let reloaded = try repository.all().first { $0.id == note.id }
        let reloadedAttributed = NoteRTF.attributedString(from: reloaded?.bodyRTF ?? Data())

        #expect(reloadedAttributed.string == "Buy milk")
        let font = reloadedAttributed.length > 0
            ? reloadedAttributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
            : nil
        #expect(font.map { NSFontManager.shared.traits(of: $0).contains(.boldFontMask) } == true)
    }
}

@Suite("FTS search")
struct GRDBNoteRepositorySearchTests {
    @Test("finds a note by a word in its body")
    func findsByBodyWord() throws {
        let repository = try makeRepository()
        var note = try repository.create()
        note.bodyRTF = rtf("Remember to buy oat milk tomorrow")
        note.bodyPlain = "Remember to buy oat milk tomorrow"
        try repository.update(note)

        let results = try repository.search("oat")

        #expect(results.contains { $0.id == note.id })
    }

    @Test("does not find a deleted note")
    func excludesDeleted() throws {
        let repository = try makeRepository()
        var note = try repository.create()
        note.bodyRTF = rtf("Remember to buy oat milk tomorrow")
        note.bodyPlain = "Remember to buy oat milk tomorrow"
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
        note.bodyRTF = rtf("Remember to buy oat milk")
        note.bodyPlain = "Remember to buy oat milk"
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
        note.bodyRTF = rtf("anything")
        note.bodyPlain = "anything"
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

@Suite("RTF migration")
struct NoteBodyRTFMigrationTests {
    /// Reproduces exactly what a real upgrade sees: a database that only
    /// ever knew the old plain-text `body` column, with a note the user
    /// actually wrote something into. Migrating it forward must convert that
    /// text into `body_rtf` rather than losing it or leaving it blank.
    @Test("migrating an existing plain-text body converts it into body_rtf without losing the text")
    func migratesExistingPlainTextBody() throws {
        let dbQueue = try DatabaseQueue()
        try Migrations.migrator.migrate(dbQueue, upTo: NoteSchema.migrationName)

        let noteID = "legacy-note"
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO note (id, title, body, body_plain, is_pinned, sort_order, created_at, updated_at)
                VALUES (?, ?, ?, ?, 0, 0, ?, ?)
                """,
                arguments: [
                    noteID, "Untitled",
                    "Remember to feed the cat", "Remember to feed the cat",
                    Date(), Date(),
                ]
            )
        }

        try Migrations.migrator.migrate(dbQueue)

        let rtfData = try dbQueue.read { db in
            try Data.fetchOne(db, sql: "SELECT body_rtf FROM note WHERE id = ?", arguments: [noteID])
        }
        #expect(rtfData != nil)
        #expect(NoteRTF.plainText(fromRTF: rtfData ?? Data()) == "Remember to feed the cat")

        // `NoteRow` no longer declares a `body` column at all — confirms the
        // migration actually dropped it rather than leaving it dangling.
        let repository = GRDBNoteRepository(dbQueue: dbQueue)
        let migratedNote = try repository.all().first { $0.id == noteID }
        #expect(migratedNote?.bodyPlain == "Remember to feed the cat")
    }
}
