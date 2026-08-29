import Foundation
import Testing
@testable import NotebarCore

/// Covers `LinkTombstone.isTombstone(url:existingTargets:)` — the pure
/// predicate behind spec §6.4 deliverable 3's tombstones, split out from
/// the AppKit styling that actually paints one (`NoteChipStyling`, in the
/// app target, untestable here — see that file's doc comment on why the
/// split exists).
@Suite("LinkTombstone")
struct LinkTombstoneTests {
    @Test("a chip whose target is in existingTargets is not a tombstone")
    func targetExists() throws {
        let target = LinkTarget(type: .note, id: "note-1")
        let url = LinkURL.url(for: target)
        #expect(LinkTombstone.isTombstone(url: url, existingTargets: [target]) == false)
    }

    @Test("a chip whose target is missing from existingTargets is a tombstone")
    func targetMissing() throws {
        let target = LinkTarget(type: .task, id: "task-1")
        let url = LinkURL.url(for: target)
        #expect(LinkTombstone.isTombstone(url: url, existingTargets: []) == true)
    }

    @Test("existingTargets is checked per-type: a note id existing as a task id doesn't count")
    func typeMatters() throws {
        let target = LinkTarget(type: .note, id: "shared-id")
        let url = LinkURL.url(for: target)
        let existingTargets: Set<LinkTarget> = [LinkTarget(type: .task, id: "shared-id")]
        #expect(LinkTombstone.isTombstone(url: url, existingTargets: existingTargets) == true)
    }

    @Test("a URL this app never wrote is neither a chip nor a tombstone")
    func notAChip() throws {
        let url = URL(string: "https://example.com")!
        #expect(LinkTombstone.isTombstone(url: url, existingTargets: []) == nil)
    }
}
