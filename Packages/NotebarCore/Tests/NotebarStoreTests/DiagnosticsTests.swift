import AppKit
import Foundation
import Testing
import GRDB
@testable import NotebarCore
@testable import NotebarStore

/// Covers the one invariant Export Diagnostics (spec §6.4b) depends on:
/// the environment block a diagnostics export contains must never carry a
/// note or task's actual content, no matter what is sitting in the
/// database it was generated from.
@Suite("Diagnostics")
struct DiagnosticsTests {
    @Test("appliedMigrations lists every registered migration for a fresh database")
    func snapshotReportsAppliedMigrations() throws {
        let dbQueue = try DatabaseQueue()
        try Migrations.migrator.migrate(dbQueue)
        let repository = GRDBDiagnosticsRepository(dbQueue: dbQueue, path: nil)

        let snapshot = try repository.snapshot()

        #expect(snapshot.appliedMigrations.contains(NoteSchema.migrationName))
        #expect(snapshot.appliedMigrations.contains(TaskSchema.migrationName))
        #expect(snapshot.appliedMigrations.contains(NoteBodyRTFDSchema.migrationName))
        #expect(snapshot.path == nil)
        #expect(snapshot.sizeOnDisk == nil)
    }

    @Test("the rendered environment block contains no note content, even with real notes in the database")
    func renderedEnvironmentExcludesNoteContent() throws {
        let dbQueue = try DatabaseQueue()
        try Migrations.migrator.migrate(dbQueue)

        let secretTitle = "SECRET_TITLE_do_not_leak"
        let secretBody = "SECRET_BODY_do_not_leak_either"
        let noteRepository = GRDBNoteRepository(dbQueue: dbQueue)
        var note = try noteRepository.create()
        note.title = secretTitle
        note.bodyRTF = NoteRTF.rtfdData(from: NSAttributedString(string: secretBody))
        note.bodyPlain = secretBody
        try noteRepository.update(note)

        let diagnosticsRepository = GRDBDiagnosticsRepository(dbQueue: dbQueue, path: nil)
        let database = try diagnosticsRepository.snapshot()

        // Fabricated environment values, standing in for what the app
        // target would actually gather from Bundle/ProcessInfo/NSScreen —
        // none of that machinery is available to this test target, and
        // none of it is what this test is checking anyway.
        let environment = DiagnosticsEnvironment(
            appVersion: "0.1.0",
            buildNumber: "1",
            osVersion: "macOS 15.0 (Build 24A000)",
            displayGeometry: ["1728x1117 @ (0, 0), scale 2.0"],
            database: database
        )

        let rendered = environment.renderedText

        #expect(!rendered.contains(secretTitle))
        #expect(!rendered.contains(secretBody))
        // Sanity check the test would actually have caught a leak: the
        // secret strings really did make it into the database this
        // snapshot was taken from.
        #expect(try noteRepository.fetch(id: note.id)?.title == secretTitle)
    }
}
