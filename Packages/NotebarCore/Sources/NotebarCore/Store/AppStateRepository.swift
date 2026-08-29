import Foundation

/// Storage for small persisted app preferences (spec §5's `app_state`
/// key/value table) — one storage story for everything the app remembers,
/// rather than splitting it across `UserDefaults` and the database. See
/// `NoteRepository` for why this is synchronous and why it lives here rather
/// than importing GRDB directly.
public protocol AppStateRepository {
    /// The persisted theme choice (spec §6.5). Falls back to `Theme.default`
    /// both when nothing has been saved yet and when the saved value is no
    /// longer recognised — someone hand-editing the database must get the
    /// default appearance back, not a crash.
    func theme() throws -> Theme

    /// Persists the theme choice.
    func setTheme(_ theme: Theme) throws
}
