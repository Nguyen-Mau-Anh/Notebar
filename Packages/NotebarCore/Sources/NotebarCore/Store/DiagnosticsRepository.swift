import Foundation

/// Storage for `DatabaseDiagnostics`, defined here for the same reason every
/// other repository protocol is (`NoteRepository`'s doc comment): so
/// `NotebarStore`'s GRDB implementation has a contract to satisfy without
/// this module ever importing GRDB (spec §3, rule 1).
public protocol DiagnosticsRepository {
    /// A fresh snapshot of the database's diagnostic facts — path, size,
    /// applied migrations — for Settings → Data and Export Diagnostics
    /// (spec §6.4b). Never includes note or task content.
    func snapshot() throws -> DatabaseDiagnostics
}
