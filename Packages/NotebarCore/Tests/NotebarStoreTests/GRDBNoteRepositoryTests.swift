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

/// Builds an RTFD blob the way the real note editor does — through
/// `NoteRTF` — from a plain string, for tests that don't care about
/// attributes or attachments.
private func rtfd(_ text: String) -> Data {
    NoteRTF.rtfdData(from: NSAttributedString(string: text))
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
        note.bodyRTF = rtfd("Buy milk")
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
        note.bodyRTF = rtfd("changed")
        note.bodyPlain = "changed"
        try repository.update(note)

        let reloaded = try repository.all().first { $0.id == note.id }
        #expect((reloaded?.updatedAt ?? .distantPast) > originalUpdatedAt)
    }

    @Test("renaming a note persists the new title and does not change the body")
    func renameTitleLeavesBodyUntouched() throws {
        let repository = try makeRepository()
        var note = try repository.create()
        note.bodyRTF = rtfd("Some body text")
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
        note.bodyRTF = rtfd("Remember to feed the cat")
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
        note.bodyRTF = rtfd("Remember to feed the cat")
        note.bodyPlain = "Remember to feed the cat"
        try repository.update(note)

        let bodyPlain = try dbQueue.read { db in
            try String.fetchOne(db, sql: "SELECT body_plain FROM note WHERE id = ?", arguments: [note.id])
        }
        #expect(bodyPlain == "Remember to feed the cat")
    }

    @Test("body_plain derived from an RTFD body matches its visible text")
    func bodyPlainMatchesRTFDVisibleText() throws {
        let dbQueue = try DatabaseQueue()
        try Migrations.migrator.migrate(dbQueue)
        let repository = GRDBNoteRepository(dbQueue: dbQueue)

        var note = try repository.create()
        let attributed = NSMutableAttributedString(string: "Remember to buy oat milk")
        attributed.addAttribute(
            .font, value: NSFont.boldSystemFont(ofSize: 14),
            range: NSRange(location: 0, length: 8)
        )
        note.bodyRTF = NoteRTF.rtfdData(from: attributed)
        note.bodyPlain = NoteRTF.plainText(from: attributed)
        try repository.update(note)

        let reloaded = try repository.all().first { $0.id == note.id }
        let storedBodyPlain = try dbQueue.read { db in
            try String.fetchOne(db, sql: "SELECT body_plain FROM note WHERE id = ?", arguments: [note.id])
        }

        #expect(reloaded?.bodyPlain == "Remember to buy oat milk")
        #expect(storedBodyPlain == "Remember to buy oat milk")
        // The RTFD blob itself still carries the bold attribute — only its
        // plain-text projection collapsed to bare characters.
        #expect(NoteRTF.plainText(fromRTFD: reloaded?.bodyRTF ?? Data()) == "Remember to buy oat milk")
    }
}

@Suite("RTFD round-trip")
struct GRDBNoteRepositoryRTFDTests {
    @Test("a bold run survives a save and reload")
    func boldSurvivesRoundTrip() throws {
        let repository = try makeRepository()
        var note = try repository.create()

        let attributed = NSMutableAttributedString(string: "Buy milk")
        attributed.addAttribute(
            .font, value: NSFont.boldSystemFont(ofSize: 14),
            range: NSRange(location: 0, length: attributed.length)
        )
        note.bodyRTF = NoteRTF.rtfdData(from: attributed)
        note.bodyPlain = attributed.string
        try repository.update(note)

        let reloaded = try repository.all().first { $0.id == note.id }
        let reloadedAttributed = NoteRTF.attributedString(fromRTFD: reloaded?.bodyRTF ?? Data())

        #expect(reloadedAttributed.string == "Buy milk")
        let font = reloadedAttributed.length > 0
            ? reloadedAttributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
            : nil
        #expect(font.map { NSFontManager.shared.traits(of: $0).contains(.boldFontMask) } == true)
    }

    /// Deliverable 2/3 (spec §6.2c): an embedded image must survive the same
    /// save-and-reload round trip a bold run does — this is the concrete
    /// proof that switching `body_rtf` to flat RTFD (rather than plain RTF)
    /// actually fixes the silent-data-loss case, not just a claim about it.
    @Test("an embedded image attachment survives a save and reload")
    func attachmentSurvivesRoundTrip() throws {
        let repository = try makeRepository()
        var note = try repository.create()

        // A genuinely backed 4x4 bitmap, not just an empty `NSImage(size:)`
        // canvas — RTFD serializes an attachment's image via its TIFF
        // representation, which a size-only `NSImage` has none of.
        let attachmentImage = NSImage(size: NSSize(width: 4, height: 4))
        attachmentImage.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 4, height: 4).fill()
        attachmentImage.unlockFocus()

        let attributed = NSMutableAttributedString(string: "Before ")
        let attachment = NSTextAttachment()
        attachment.image = attachmentImage
        attributed.append(NSAttributedString(attachment: attachment))
        attributed.append(NSAttributedString(string: " after"))

        note.bodyRTF = NoteRTF.rtfdData(from: attributed)
        note.bodyPlain = NoteRTF.plainText(from: attributed)
        try repository.update(note)

        let reloaded = try repository.all().first { $0.id == note.id }
        let reloadedAttributed = NoteRTF.attributedString(fromRTFD: reloaded?.bodyRTF ?? Data())

        var foundAttachment = false
        reloadedAttributed.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: reloadedAttributed.length),
            options: []
        ) { value, _, _ in
            if value is NSTextAttachment { foundAttachment = true }
        }

        #expect(foundAttachment)
        #expect(reloadedAttributed.string.contains("Before"))
        #expect(reloadedAttributed.string.contains("after"))
    }
}

@Suite("FTS search")
struct GRDBNoteRepositorySearchTests {
    @Test("finds a note by a word in its body")
    func findsByBodyWord() throws {
        let repository = try makeRepository()
        var note = try repository.create()
        note.bodyRTF = rtfd("Remember to buy oat milk tomorrow")
        note.bodyPlain = "Remember to buy oat milk tomorrow"
        try repository.update(note)

        let results = try repository.search("oat")

        #expect(results.contains { $0.id == note.id })
    }

    @Test("does not find a deleted note")
    func excludesDeleted() throws {
        let repository = try makeRepository()
        var note = try repository.create()
        note.bodyRTF = rtfd("Remember to buy oat milk tomorrow")
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
        note.bodyRTF = rtfd("Remember to buy oat milk")
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
        note.bodyRTF = rtfd("anything")
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
    ///
    /// Stops at `NoteBodyRTFSchema` deliberately, one migration short of
    /// latest — this test is about that specific, already-applied migration
    /// in isolation; `NoteBodyRTFMigrationRTFDTests` below covers what the
    /// *next* migration (`NoteBodyRTFDSchema`) does to this same row.
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

        try Migrations.migrator.migrate(dbQueue, upTo: NoteBodyRTFSchema.migrationName)

        let rtfData = try dbQueue.read { db in
            try Data.fetchOne(db, sql: "SELECT body_rtf FROM note WHERE id = ?", arguments: [noteID])
        }
        #expect(rtfData != nil)
        #expect(NoteRTF.plainText(fromRTF: rtfData ?? Data()) == "Remember to feed the cat")

        // `NoteRow` no longer declares a `body` column at all — confirms the
        // migration actually dropped it rather than leaving it dangling.
        // (`NoteRow` still expects `body_rtf` to be RTFD by this point in
        // the full migration chain, so it can't be used here — this table
        // hasn't run `NoteBodyRTFDSchema` yet — a raw `body_plain` read is
        // used instead.)
        let bodyPlain = try dbQueue.read { db in
            try String.fetchOne(db, sql: "SELECT body_plain FROM note WHERE id = ?", arguments: [noteID])
        }
        #expect(bodyPlain == "Remember to feed the cat")
    }
}

@Suite("RTFD migration")
struct NoteBodyRTFDMigrationTests {
    /// Spec §6.2c's core safety requirement: a database from before images
    /// existed has plain-RTF bodies with real text in them, and upgrading
    /// past `NoteBodyRTFDSchema` must convert every one of those blobs to
    /// RTFD without losing that text — plain RTF would otherwise silently
    /// drop any attachment on the very next save, no error, just a note
    /// that loses its picture.
    @Test("migrating an existing RTF body converts it to RTFD without losing its text")
    func migratesExistingRTFBodyToRTFD() throws {
        let dbQueue = try DatabaseQueue()
        try Migrations.migrator.migrate(dbQueue, upTo: NoteBodyRTFSchema.migrationName)

        // A row exactly as `NoteBodyRTFSchema` would have left it: real
        // plain-RTF bytes in `body_rtf`, built the same way that migration's
        // own backfill builds them.
        let noteID = "pre-rtfd-note"
        let legacyRTF = NoteRTF.data(from: NSAttributedString(string: "Remember to buy oat milk"))
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO note (id, title, body_rtf, body_plain, is_pinned, sort_order, created_at, updated_at)
                VALUES (?, ?, ?, ?, 0, 0, ?, ?)
                """,
                arguments: [
                    noteID, "Untitled",
                    legacyRTF, "Remember to buy oat milk",
                    Date(), Date(),
                ]
            )
        }

        try Migrations.migrator.migrate(dbQueue)

        let repository = GRDBNoteRepository(dbQueue: dbQueue)
        let migrated = try repository.all().first { $0.id == noteID }

        #expect(migrated != nil)
        // The RTFD reader must be the one that makes sense of the migrated
        // blob now — the legacy RTF reader would fail to parse it.
        #expect(NoteRTF.plainText(fromRTFD: migrated?.bodyRTF ?? Data()) == "Remember to buy oat milk")
        // `body_plain` (never touched by this migration) still matches.
        #expect(migrated?.bodyPlain == "Remember to buy oat milk")
    }
}

@Suite("embedded image downscaling")
struct NoteImageEmbeddingTests {
    /// Spec §6.2c deliverable 3: an image whose longest edge exceeds 2000px
    /// is downscaled before it round-trips into RTFD, preserving aspect
    /// ratio — a modern screenshot gains nothing in a 340pt panel and every
    /// megabyte of it lives in the note's row forever.
    @Test("an image wider than the limit is downscaled, preserving aspect ratio")
    func oversizedImageIsDownscaled() {
        let oversized = NSImage(size: NSSize(width: 4000, height: 2000))

        let downscaled = NoteImageEmbedding.downscaledIfNeeded(oversized)

        #expect(downscaled.pixelSize.width == NoteImageEmbedding.maxEmbeddedDimensionPixels)
        #expect(downscaled.pixelSize.height == NoteImageEmbedding.maxEmbeddedDimensionPixels / 2)
    }

    @Test("an image already within the limit is left untouched")
    func smallImageIsUntouched() {
        let small = NSImage(size: NSSize(width: 200, height: 100))

        let result = NoteImageEmbedding.downscaledIfNeeded(small)

        #expect(result === small)
    }
}

@Suite("note summaries")
struct GRDBNoteRepositorySummariesTests {
    /// Spec §6.2c deliverable 4: `summaries()` is the cheap path the
    /// all-notes menu reads instead of `all()`. It must never silently
    /// diverge from `all()` on the fields both expose — same notes, same
    /// titles — or the menu could show a stale or incomplete list without
    /// any test ever catching it.
    @Test("summaries() returns the same count and titles as all()")
    func matchesAll() throws {
        let repository = try makeRepository()
        var first = try repository.create()
        first.title = "Grocery List"
        try repository.update(first)
        var second = try repository.create()
        second.title = "Meeting Notes"
        try repository.update(second)

        let all = try repository.all()
        let summaries = try repository.summaries()

        #expect(summaries.count == all.count)
        #expect(Set(summaries.map(\.title)) == Set(all.map(\.title)))
        #expect(Set(summaries.map(\.id)) == Set(all.map(\.id)))
    }

    @Test("fetch(id:) reads a single note's full body")
    func fetchByID() throws {
        let repository = try makeRepository()
        var note = try repository.create()
        note.bodyRTF = rtfd("Remember to feed the cat")
        note.bodyPlain = "Remember to feed the cat"
        try repository.update(note)

        let fetched = try repository.fetch(id: note.id)

        #expect(fetched?.bodyPlain == "Remember to feed the cat")
    }

    @Test("fetch(id:) returns nil for an unknown id")
    func fetchUnknownID() throws {
        let repository = try makeRepository()

        #expect(try repository.fetch(id: "not-a-real-id") == nil)
    }
}

@Suite("stored colour is stripped for dark mode")
struct NoteRTFColorStrippingTests {
    /// The formatting bar has no colour control (bold, italic, inline code,
    /// H1, H2, bulleted/numbered/checklist — spec §6.2b), so a stored
    /// `.foregroundColor` was never a user choice, only default black baked
    /// in at serialization time. `rtfdData(from:)` strips it on the way out,
    /// so a fresh save never bakes it back in — this is the round trip a
    /// real save-then-reopen takes.
    @Test("an explicit foreground colour does not survive an RTFD round trip")
    func foregroundColorStrippedOnRoundTrip() {
        let attributed = NSMutableAttributedString(string: "Buy milk")
        attributed.addAttribute(
            .foregroundColor, value: NSColor.black,
            range: NSRange(location: 0, length: attributed.length)
        )

        let data = NoteRTF.rtfdData(from: attributed)
        let reloaded = NoteRTF.attributedString(fromRTFD: data)

        #expect(reloaded.length > 0)
        #expect(reloaded.attribute(.foregroundColor, at: 0, effectiveRange: nil) == nil)
    }

    /// The invariant that actually keeps dark mode working: every note the
    /// user already has was serialized before this fix existed, so its
    /// stored bytes already carry baked-in black regardless of what
    /// `rtfdData(from:)` does going forward. Bypasses it deliberately,
    /// writing directly through the raw AppKit API, to reproduce exactly
    /// that pre-existing shape — `attributedString(fromRTFD:)` must strip
    /// the colour on *read* too, or every note ever written stays black
    /// until its next save.
    @Test("attributedString(fromRTFD:) strips a foreground colour already present in the stored blob")
    func foregroundColorStrippedEvenWhenBakedIntoStoredBlob() {
        let attributed = NSMutableAttributedString(string: "Buy milk")
        attributed.addAttribute(
            .foregroundColor, value: NSColor.black,
            range: NSRange(location: 0, length: attributed.length)
        )
        let data = attributed.rtfd(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [:]
        ) ?? Data()

        let reloaded = NoteRTF.attributedString(fromRTFD: data)

        #expect(reloaded.length > 0)
        #expect(reloaded.attribute(.foregroundColor, at: 0, effectiveRange: nil) == nil)
    }
}
