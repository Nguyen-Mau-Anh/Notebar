import os

/// Centralized `os.Logger` definitions for Notebar's unified-log diagnostics
/// (spec §6.4b) — one category per area, all under a single subsystem so
/// Export Diagnostics and `log show --predicate 'subsystem == "\(subsystem)"'`
/// can pull the whole app's history in one query.
///
/// Lives in `NotebarStore`, not `NotebarCore`: `os.Logger` is Apple-only —
/// there is no counterpart on Linux or Windows — and `NotebarCore` must stay
/// portable for the M5 Windows port (spec section 3, rule 1). Note that
/// `scripts/check-core-purity.sh`'s import scan only bans AppKit/SwiftUI/
/// UIKit/Cocoa and would not itself catch `import os` landing in
/// `NotebarCore` — this placement is a judgment call the script can't
/// enforce, not something it happens to already reject. `NotebarStore`
/// already carries Apple-only dependencies (AppKit for RTF, GRDB) and was
/// never a candidate for that port, so it — and the app target, which
/// depends on it — is where the concrete logger belongs. `NotebarCore`
/// itself has no I/O and nothing to report today; if that changes, the
/// pattern to follow is a small logging protocol defined there, with this
/// enum's loggers as one implementation of it, not an `import os` added to
/// that target.
///
/// **Never log note or task content** — no titles, bodies, or task details,
/// in any category, at any level. The unified log is exportable (Settings →
/// Data → Export Diagnostics) and the user may hand the result to someone
/// else. Log ids and counts instead of the content behind them.
///
/// Also remember `Logger`'s string interpolation defaults every
/// non-literal value to `privacy: .private` (redacted as `<private>` in an
/// exported log unless the process holds a special profile). None of what
/// this app logs is actually sensitive — ids, counts, error descriptions,
/// state names — so every interpolated value at a call site should be
/// marked `privacy: .public` explicitly, or Export Diagnostics quietly
/// produces a file with nothing useful in it.
public enum NotebarLog {
    public static let subsystem = "com.anhnm.notebar"

    /// The edge panel's state machine and window geometry — expand/collapse
    /// transitions, timers, the trigger band.
    public static let panel = Logger(subsystem: subsystem, category: "panel")
    /// Note create/delete/open, persistence, and the all-notes menu.
    public static let notes = Logger(subsystem: subsystem, category: "notes")
    /// Task/board create/delete/move and persistence.
    public static let tasks = Logger(subsystem: subsystem, category: "tasks")
    /// The GRDB-backed store itself: opening the database, migrations,
    /// theme persistence.
    public static let store = Logger(subsystem: subsystem, category: "store")
    /// App lifecycle: launch, the global hotkey, the status item.
    public static let app = Logger(subsystem: subsystem, category: "app")
}
