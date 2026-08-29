import Foundation

/// Storage for the open-tab strip (spec §5's `open_tab` table, spec §2
/// decision 3: open tabs persist across restarts). See `NoteRepository` for
/// why this is synchronous and why it lives here rather than importing GRDB
/// directly.
public protocol OpenTabRepository {
    /// Every open tab, ordered by `sortOrder` ascending.
    func all() throws -> [OpenTab]

    /// Replaces the entire open-tab set in one transaction. The strip is
    /// small (a handful of tabs) and changes only on structural events —
    /// open, close, reorder, select — never per keystroke, so a full
    /// replace is simpler than diffing and cheap enough not to matter.
    func replaceAll(_ tabs: [OpenTab]) throws
}
