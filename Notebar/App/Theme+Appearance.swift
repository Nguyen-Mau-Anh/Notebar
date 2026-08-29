import AppKit
import NotebarCore

/// The `NSApp.appearance` mapping for `Theme` (spec §6.5). Lives in the app
/// target rather than `NotebarCore` — `NSAppearance` is AppKit, and that
/// module never imports it (spec §3, rule 1).
extension Theme {
    /// `nil` for `.system` is the whole point: it hands appearance back to
    /// macOS, so the app tracks the user's setting live, including the
    /// automatic day/night schedule. Resolving "what is macOS's appearance
    /// right now" once and assigning that instead would freeze the app at
    /// whatever was current at that moment and silently stop following it.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}
