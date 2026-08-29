import Foundation

/// A status column on a `Board` (spec §5's `board_column` table). `kind`
/// drives the one behaviour rule the repository owns — moving a task into a
/// `doneKind` column stamps `completedAt`, moving it out clears it (spec
/// §6.3a) — so it is a string constant rather than a fixed enum, the same
/// reasoning `OpenTab.noteKind` uses: it is schema data a future board
/// could extend, not a closed set the type system should own.
public struct BoardColumn: Identifiable, Equatable, Sendable {
    public var id: String
    public var boardID: String
    public var name: String
    public var kind: String
    public var sortOrder: Double
    public var wipLimit: Int?

    public init(
        id: String = UUID().uuidString,
        boardID: String,
        name: String,
        kind: String,
        sortOrder: Double,
        wipLimit: Int? = nil
    ) {
        self.id = id
        self.boardID = boardID
        self.name = name
        self.kind = kind
        self.sortOrder = sortOrder
        self.wipLimit = wipLimit
    }
}

public extension BoardColumn {
    /// Not-yet-started work. Seeded as "Queue".
    static let backlogKind = "backlog"
    /// In-progress work. Seeded as "Working".
    static let activeKind = "active"
    /// Finished work. Seeded as "Done" — the kind `GRDBTaskRepository`
    /// checks to decide whether a moved task's `completedAt` is stamped or
    /// cleared.
    static let doneKind = "done"
}
