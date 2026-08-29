import Testing
import GRDB
@testable import NotebarCore
@testable import NotebarStore

@Suite("GRDBAppStateRepository")
struct GRDBAppStateRepositoryTests {
    private func makeRepository() throws -> GRDBAppStateRepository {
        let dbQueue = try DatabaseQueue()
        try Migrations.migrator.migrate(dbQueue)
        return GRDBAppStateRepository(dbQueue: dbQueue)
    }

    @Test("a fresh database with no saved theme returns the default (System)")
    func unsetKeyReturnsDefault() throws {
        #expect(try makeRepository().theme() == .default)
        #expect(Theme.default == .system)
    }

    @Test("setTheme round-trips through theme()")
    func roundTrips() throws {
        let repository = try makeRepository()

        try repository.setTheme(.dark)
        #expect(try repository.theme() == .dark)

        try repository.setTheme(.light)
        #expect(try repository.theme() == .light)
    }

    @Test("an unrecognised stored value falls back to System rather than crashing")
    func unrecognisedValueFallsBackToDefault() throws {
        let dbQueue = try DatabaseQueue()
        try Migrations.migrator.migrate(dbQueue)
        // Simulates someone hand-editing the database to a value no longer
        // (or never) a valid `Theme` case.
        try dbQueue.write { db in
            try AppStateRow(key: AppStateSchema.themeKey, value: "sepia").save(db)
        }

        let repository = GRDBAppStateRepository(dbQueue: dbQueue)
        #expect(try repository.theme() == .system)
    }
}
