import Foundation
import Testing
import GRDB
@testable import NotebarCore
@testable import NotebarStore

/// Every test opens its own in-memory database — fast, and isolated from
/// every other test, so ordering never matters. See `GRDBNoteRepositoryTests`
/// for the pattern this mirrors.
private func makeRepository() throws -> GRDBTaskRepository {
    let dbQueue = try DatabaseQueue()
    try Migrations.migrator.migrate(dbQueue)
    return GRDBTaskRepository(dbQueue: dbQueue)
}

@Suite("seeded board columns")
struct GRDBTaskRepositorySeedTests {
    @Test("the three columns seed exactly once, even if migrations run twice")
    func seedsOnce() throws {
        let dbQueue = try DatabaseQueue()
        try Migrations.migrator.migrate(dbQueue)
        try Migrations.migrator.migrate(dbQueue)

        let repository = GRDBTaskRepository(dbQueue: dbQueue)
        let columns = try repository.columns()

        #expect(columns.count == 3)
        #expect(columns.map(\.name) == ["Queue", "Working", "Done"])
        #expect(columns.map(\.kind) == [BoardColumn.backlogKind, BoardColumn.activeKind, BoardColumn.doneKind])
    }
}

@Suite("GRDBTaskRepository CRUD")
struct GRDBTaskRepositoryCRUDTests {
    @Test("a created task round-trips through all(), grouped by its column")
    func createThenRead() throws {
        let repository = try makeRepository()
        let queue = try #require(try repository.columns().first { $0.kind == BoardColumn.backlogKind })

        let created = try repository.create(title: "Buy milk", columnID: queue.id)

        let all = try repository.all()
        #expect(all.count == 1)
        #expect(all.first?.id == created.id)
        #expect(all.first?.columnID == queue.id)
        #expect(all.first?.title == "Buy milk")
    }

    @Test("create with an unknown column id throws")
    func createUnknownColumn() throws {
        let repository = try makeRepository()
        #expect(throws: (any Error).self) {
            try repository.create(title: "Buy milk", columnID: "not-a-real-column")
        }
    }

    @Test("update persists new field values")
    func update() throws {
        let repository = try makeRepository()
        let queue = try #require(try repository.columns().first { $0.kind == BoardColumn.backlogKind })
        var task = try repository.create(title: "Buy milk", columnID: queue.id)
        task.title = "Buy oat milk"
        task.detailPlain = "Two cartons"
        task.priority = 2

        try repository.update(task)

        let reloaded = try repository.all().first { $0.id == task.id }
        #expect(reloaded?.title == "Buy oat milk")
        #expect(reloaded?.detailPlain == "Two cartons")
        #expect(reloaded?.priority == 2)
    }

    @Test("renaming — updating only the title — leaves the detail untouched")
    func renamePreservesDetail() throws {
        let repository = try makeRepository()
        let queue = try #require(try repository.columns().first { $0.kind == BoardColumn.backlogKind })
        var task = try repository.create(title: "Buy milk", columnID: queue.id)
        task.detailPlain = "Two cartons, oat if they have it"
        try repository.update(task)

        // Mirrors `PanelViewModel.renameTask`: only `title` changes on the
        // in-memory copy before it's persisted.
        task.title = "Buy oat milk"
        try repository.update(task)

        let reloaded = try repository.all().first { $0.id == task.id }
        #expect(reloaded?.title == "Buy oat milk")
        #expect(reloaded?.detailPlain == "Two cartons, oat if they have it")
    }

    @Test("update on an unknown id throws")
    func updateUnknownID() throws {
        let repository = try makeRepository()
        let queue = try #require(try repository.columns().first { $0.kind == BoardColumn.backlogKind })
        let ghost = TaskItem(id: "missing", title: "Ghost", columnID: queue.id)
        #expect(throws: (any Error).self) {
            try repository.update(ghost)
        }
    }

    @Test("delete removes the task")
    func delete() throws {
        let repository = try makeRepository()
        let queue = try #require(try repository.columns().first { $0.kind == BoardColumn.backlogKind })
        let task = try repository.create(title: "Buy milk", columnID: queue.id)

        try repository.delete(id: task.id)

        #expect(try repository.all().isEmpty)
    }

    @Test("deleting an unknown id is a no-op")
    func deleteUnknownID() throws {
        let repository = try makeRepository()
        let queue = try #require(try repository.columns().first { $0.kind == BoardColumn.backlogKind })
        _ = try repository.create(title: "Buy milk", columnID: queue.id)

        try repository.delete(id: "not-a-real-id")

        #expect(try repository.all().count == 1)
    }
}

@Suite("moving a task stamps completedAt")
struct GRDBTaskRepositoryMoveTests {
    @Test("moving a task to the Done column stamps completedAt; moving it back to Working clears it")
    func completedAtLifecycle() throws {
        let repository = try makeRepository()
        let columns = try repository.columns()
        let queue = try #require(columns.first { $0.kind == BoardColumn.backlogKind })
        let working = try #require(columns.first { $0.kind == BoardColumn.activeKind })
        let done = try #require(columns.first { $0.kind == BoardColumn.doneKind })

        let task = try repository.create(title: "Ship it", columnID: queue.id)
        #expect(task.completedAt == nil)

        let movedToDone = try repository.move(id: task.id, columnID: done.id, before: nil, after: nil)
        #expect(movedToDone.completedAt != nil)
        #expect(movedToDone.columnID == done.id)

        let movedBack = try repository.move(id: task.id, columnID: working.id, before: nil, after: nil)
        #expect(movedBack.completedAt == nil)
        #expect(movedBack.columnID == working.id)
    }

    @Test("moving an unknown task id throws")
    func moveUnknownTask() throws {
        let repository = try makeRepository()
        let done = try #require(try repository.columns().first { $0.kind == BoardColumn.doneKind })
        #expect(throws: (any Error).self) {
            try repository.move(id: "not-a-real-task", columnID: done.id, before: nil, after: nil)
        }
    }

    @Test("moving into an unknown column id throws")
    func moveUnknownColumn() throws {
        let repository = try makeRepository()
        let queue = try #require(try repository.columns().first { $0.kind == BoardColumn.backlogKind })
        let task = try repository.create(title: "Ship it", columnID: queue.id)
        #expect(throws: (any Error).self) {
            try repository.move(id: task.id, columnID: "not-a-real-column", before: nil, after: nil)
        }
    }
}

@Suite("fractional sortOrder")
struct GRDBTaskRepositorySortOrderTests {
    @Test("moving between two tasks in the same column yields a value strictly between theirs")
    func moveBetween() throws {
        let repository = try makeRepository()
        let queue = try #require(try repository.columns().first { $0.kind == BoardColumn.backlogKind })
        let first = try repository.create(title: "First", columnID: queue.id)
        let second = try repository.create(title: "Second", columnID: queue.id)
        #expect(first.sortOrder < second.sortOrder)

        let third = try repository.create(title: "Third", columnID: queue.id)
        let moved = try repository.move(id: third.id, columnID: queue.id, before: first.id, after: second.id)

        #expect(moved.sortOrder > first.sortOrder)
        #expect(moved.sortOrder < second.sortOrder)
    }

    @Test("moving into an empty column — no neighbours on either side — settles on sort_order 0")
    func moveIntoEmptyColumn() throws {
        let repository = try makeRepository()
        let queue = try #require(try repository.columns().first { $0.kind == BoardColumn.backlogKind })
        let working = try #require(try repository.columns().first { $0.kind == BoardColumn.activeKind })
        let task = try repository.create(title: "First into Working", columnID: queue.id)

        // `before` and `after` are both nil: the board's own drop handler
        // passes `after: destination.tasks.last?.id`, which is nil for an
        // empty column, and `before` is always nil (dropping between two
        // existing cards isn't part of this deliverable).
        let moved = try repository.move(id: task.id, columnID: working.id, before: nil, after: nil)

        #expect(moved.columnID == working.id)
        #expect(moved.sortOrder == 0)
    }
}

@Suite("FTS search")
struct GRDBTaskRepositorySearchTests {
    @Test("finds a task by a word in its detail")
    func findsByDetailWord() throws {
        let repository = try makeRepository()
        let queue = try #require(try repository.columns().first { $0.kind == BoardColumn.backlogKind })
        var task = try repository.create(title: "Groceries", columnID: queue.id)
        task.detailPlain = "Remember to buy oat milk tomorrow"
        try repository.update(task)

        let results = try repository.search("oat")

        #expect(results.contains { $0.id == task.id })
    }

    @Test("does not find a deleted task")
    func excludesDeleted() throws {
        let repository = try makeRepository()
        let queue = try #require(try repository.columns().first { $0.kind == BoardColumn.backlogKind })
        var task = try repository.create(title: "Groceries", columnID: queue.id)
        task.detailPlain = "Remember to buy oat milk tomorrow"
        try repository.update(task)

        try repository.delete(id: task.id)

        let results = try repository.search("oat")

        #expect(results.isEmpty)
    }

    @Test("a blank query returns no results")
    func blankQuery() throws {
        let repository = try makeRepository()
        let queue = try #require(try repository.columns().first { $0.kind == BoardColumn.backlogKind })
        _ = try repository.create(title: "Groceries", columnID: queue.id)

        #expect(try repository.search("   ").isEmpty)
    }
}
