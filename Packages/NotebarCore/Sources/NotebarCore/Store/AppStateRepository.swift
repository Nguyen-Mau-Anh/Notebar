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

    /// The persisted Activation → Open delay (spec §6.5), i.e.
    /// `PanelTiming.edgeDwell`. Falls back to `PanelTiming.edgeDwell` when
    /// nothing has been saved, and clamps to `PanelTiming.edgeDwellRange`
    /// when the saved value parses but is out of range — a hand-edited
    /// database must never be able to push the panel out of its designed
    /// feel, only the settings UI's own slider can.
    func edgeDwell() throws -> TimeInterval

    /// Persists the Open delay.
    func setEdgeDwell(_ value: TimeInterval) throws

    /// The persisted Activation → Close delay, i.e. `PanelTiming.exitDwell`.
    /// Same fallback/clamp contract as `edgeDwell()`, against
    /// `PanelTiming.exitDwellRange`.
    func exitDwell() throws -> TimeInterval

    /// Persists the Close delay.
    func setExitDwell(_ value: TimeInterval) throws

    /// The persisted Activation → Edge tolerance, i.e. `PanelTiming.exitSlop`.
    /// Same fallback/clamp contract as `edgeDwell()`, against
    /// `PanelTiming.exitSlopRange`.
    func exitSlop() throws -> CGFloat

    /// Persists the Edge tolerance.
    func setExitSlop(_ value: CGFloat) throws
}
