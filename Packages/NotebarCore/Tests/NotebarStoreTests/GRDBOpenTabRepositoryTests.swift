import Testing
import GRDB
@testable import NotebarCore
@testable import NotebarStore

@Suite("GRDBOpenTabRepository")
struct GRDBOpenTabRepositoryTests {
    private func makeRepository() throws -> GRDBOpenTabRepository {
        let dbQueue = try DatabaseQueue()
        try Migrations.migrator.migrate(dbQueue)
        return GRDBOpenTabRepository(dbQueue: dbQueue)
    }

    @Test("a fresh database has no open tabs")
    func empty() throws {
        #expect(try makeRepository().all().isEmpty)
    }

    @Test("replaceAll persists the given tabs in sort order")
    func replaceAllPersists() throws {
        let repository = try makeRepository()
        let tabs = [
            OpenTab(kind: OpenTab.noteKind, refID: "note-a", sortOrder: 0, isActive: false),
            OpenTab(kind: OpenTab.noteKind, refID: "note-b", sortOrder: 1, isActive: true),
        ]

        try repository.replaceAll(tabs)

        let reloaded = try repository.all()
        #expect(reloaded.map(\.refID) == ["note-a", "note-b"])
        #expect(reloaded.first { $0.refID == "note-b" }?.isActive == true)
    }

    @Test("replaceAll discards whatever was there before")
    func replaceAllReplaces() throws {
        let repository = try makeRepository()
        try repository.replaceAll([
            OpenTab(kind: OpenTab.noteKind, refID: "note-a", sortOrder: 0, isActive: true),
        ])

        try repository.replaceAll([
            OpenTab(kind: OpenTab.noteKind, refID: "note-b", sortOrder: 0, isActive: true),
        ])

        let reloaded = try repository.all()
        #expect(reloaded.map(\.refID) == ["note-b"])
    }
}
