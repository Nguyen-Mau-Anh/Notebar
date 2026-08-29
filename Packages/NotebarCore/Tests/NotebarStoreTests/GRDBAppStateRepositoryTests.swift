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

    // MARK: - Activation timings (spec §6.5)

    @Test("a fresh database with no saved Activation timings returns the PanelTiming defaults")
    func unsetActivationTimingsReturnDefaults() throws {
        let repository = try makeRepository()
        #expect(try repository.edgeDwell() == PanelTiming.edgeDwell)
        #expect(try repository.exitDwell() == PanelTiming.exitDwell)
        #expect(try repository.exitSlop() == PanelTiming.exitSlop)
    }

    @Test("setEdgeDwell/setExitDwell/setExitSlop round-trip through their getters")
    func activationTimingsRoundTrip() throws {
        let repository = try makeRepository()

        try repository.setEdgeDwell(0.2)
        #expect(try repository.edgeDwell() == 0.2)

        try repository.setExitDwell(0.5)
        #expect(try repository.exitDwell() == 0.5)

        try repository.setExitSlop(40)
        #expect(try repository.exitSlop() == 40)
    }

    @Test("an out-of-range stored value clamps to the PanelTiming range rather than being used as-is")
    func outOfRangeValuesClamp() throws {
        let dbQueue = try DatabaseQueue()
        try Migrations.migrator.migrate(dbQueue)
        // Simulates someone hand-editing the database past what the
        // Settings sliders themselves could ever produce — in particular an
        // `exitDwell` of 0, which would make the panel collapse the instant
        // the cursor leaves (spec §4.4's hostile behaviour).
        try dbQueue.write { db in
            try AppStateRow(key: AppStateSchema.edgeDwellKey, value: "9999").save(db)
            try AppStateRow(key: AppStateSchema.exitDwellKey, value: "0").save(db)
            try AppStateRow(key: AppStateSchema.exitSlopKey, value: "-50").save(db)
        }

        let repository = GRDBAppStateRepository(dbQueue: dbQueue)
        #expect(try repository.edgeDwell() == PanelTiming.edgeDwellRange.upperBound)
        #expect(try repository.exitDwell() == PanelTiming.exitDwellRange.lowerBound)
        #expect(try repository.exitDwell() > 0)
        #expect(try repository.exitSlop() == PanelTiming.exitSlopRange.lowerBound)
    }

    @Test("an unparseable stored value falls back to the PanelTiming default rather than crashing")
    func unparseableValuesFallBackToDefault() throws {
        let dbQueue = try DatabaseQueue()
        try Migrations.migrator.migrate(dbQueue)
        // Simulates a hand-edited database with non-numeric text in a
        // timing column.
        try dbQueue.write { db in
            try AppStateRow(key: AppStateSchema.edgeDwellKey, value: "fast").save(db)
            try AppStateRow(key: AppStateSchema.exitDwellKey, value: "").save(db)
            try AppStateRow(key: AppStateSchema.exitSlopKey, value: "wide").save(db)
        }

        let repository = GRDBAppStateRepository(dbQueue: dbQueue)
        #expect(try repository.edgeDwell() == PanelTiming.edgeDwell)
        #expect(try repository.exitDwell() == PanelTiming.exitDwell)
        #expect(try repository.exitSlop() == PanelTiming.exitSlop)
    }
}
