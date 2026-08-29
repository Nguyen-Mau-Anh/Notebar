import Foundation

/// The user's appearance preference (spec §6.5): a three-way choice between
/// following macOS's own appearance and pinning to one of its two modes.
///
/// The `NSAppearance` mapping deliberately does not live here — this module
/// never imports AppKit (spec §3, rule 1) — see the app target's
/// `Theme.nsAppearance` for that half.
public enum Theme: String, CaseIterable, Equatable, Sendable {
    /// Tracks macOS's own appearance live, including its automatic day/night
    /// schedule. The default: an overlay that floats above other apps should
    /// match them.
    case system
    case light
    case dark

    /// What `AppStateRepository.theme()` falls back to when nothing has been
    /// saved yet, or the saved value is no longer recognised.
    public static let `default`: Theme = .system
}
