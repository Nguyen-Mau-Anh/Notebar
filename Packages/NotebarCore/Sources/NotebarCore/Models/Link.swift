import Foundation

/// The two kinds of thing a `Link` can point at (spec §5's `link` table:
/// `src_type`/`dst_type`). A real enum, unlike `OpenTab.kind` or
/// `BoardColumn.kind` — those are deliberately open-ended schema data a
/// future case can extend without a type change; `link`'s two endpoints are
/// exactly notes and tasks for the whole life of this table (spec §6.4's
/// "note→task, task→note, note→note, task→task"), so closing the type over
/// them catches a typo'd `"nott"` at compile time instead of a silent
/// zero-row query at runtime.
public enum LinkEntityType: String, Codable, Equatable, Sendable {
    case note
    case task
}

/// One endpoint of a `Link` — an entity type plus its id — used by
/// `LinkRepository.outgoing(from:)`/`incoming(to:)` rather than two loose
/// parameters, so a caller can't accidentally transpose a type and an id
/// that happen to both be strings.
///
/// `Hashable` (spec §6.4 deliverable 3, tombstones): `LinkTombstone` and
/// `PanelViewModel.existingLinkTargets()` collect every note/task id that
/// still exists into a `Set<LinkTarget>` once per note load, so checking
/// whether a chip's target survived is a set lookup rather than a query per
/// chip.
public struct LinkTarget: Equatable, Hashable, Sendable {
    public var type: LinkEntityType
    public var id: String

    public init(type: LinkEntityType, id: String) {
        self.type = type
        self.id = id
    }
}

/// A single edge between two notes/tasks (spec §5's `link` table, built here
/// for the first time — see `LinkSchema`'s doc comment for why it took this
/// long). One generic table covers every direction spec §6.4 lists, so
/// `Link` itself carries no notion of "the note side" or "the task side" —
/// only `srcType`/`dstType`, exactly mirroring the columns.
public struct Link: Identifiable, Equatable, Sendable {
    public var id: String
    public var srcType: LinkEntityType
    public var srcId: String
    public var dstType: LinkEntityType
    public var dstId: String
    public var kind: String
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        srcType: LinkEntityType,
        srcId: String,
        dstType: LinkEntityType,
        dstId: String,
        kind: String = Link.referencesKind,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.srcType = srcType
        self.srcId = srcId
        self.dstType = dstType
        self.dstId = dstId
        self.kind = kind
        self.createdAt = createdAt
    }
}

public extension Link {
    /// The only `kind` any link is created with today (spec §5's `link.kind
    /// DEFAULT 'references'`). A string constant rather than an enum case,
    /// matching `OpenTab.noteKind`'s reasoning: `kind` is meant to grow
    /// (backlinks vs. a future "blocks"/"duplicates" relation) without
    /// widening a closed type every time.
    static let referencesKind = "references"

    /// The two endpoints as `LinkTarget`s, for callers that already think in
    /// terms of "where this link points" rather than its four raw columns.
    var source: LinkTarget { LinkTarget(type: srcType, id: srcId) }
    var destination: LinkTarget { LinkTarget(type: dstType, id: dstId) }
}
