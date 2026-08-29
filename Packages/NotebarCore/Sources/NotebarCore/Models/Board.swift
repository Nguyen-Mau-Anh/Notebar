import Foundation

/// A tasks board (spec §5's `board` table). v1 seeds exactly one — see
/// `TaskSchema`'s seed migration — but the schema does not assume a single
/// board, matching spec §5's shape for future multi-board support.
public struct Board: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var sortOrder: Double

    public init(
        id: String = UUID().uuidString,
        name: String,
        sortOrder: Double = 0
    ) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
    }
}
