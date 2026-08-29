import Foundation

/// A persisted entry in the open-tab strip (spec §5's `open_tab` table).
/// Spec decision 3 (§2) is that open tabs survive a restart — this is what
/// makes that possible: `kind`/`refID` point at the thing the tab shows
/// (only `.note` exists today; tasks arrive with the Tasks board), and
/// `sortOrder`/`isActive` capture the strip's order and current selection.
public struct OpenTab: Identifiable, Equatable, Sendable {
    public var id: String
    public var kind: String
    public var refID: String
    public var sortOrder: Double
    public var isActive: Bool

    public init(
        id: String = UUID().uuidString,
        kind: String,
        refID: String,
        sortOrder: Double,
        isActive: Bool
    ) {
        self.id = id
        self.kind = kind
        self.refID = refID
        self.sortOrder = sortOrder
        self.isActive = isActive
    }
}

public extension OpenTab {
    /// The only `kind` that exists in this milestone. A string constant
    /// rather than an enum, matching spec §2 decision 1's reasoning for
    /// board columns: kinds are schema data other tabs (tasks) add to later,
    /// not a fixed set the type system should close over.
    static let noteKind = "note"
}
