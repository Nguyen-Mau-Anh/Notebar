import Foundation

/// A single note. State is in-memory only for this first M1 slice — SQLite
/// lands behind repository protocols in a later task without needing this
/// shape to change.
struct Note: Identifiable {
    let id = UUID()
    var body: String = ""
    let createdAt = Date()

    /// Derived from the first non-empty line, trimmed, falling back to
    /// "Untitled" so a fresh note's tab always has a readable label and the
    /// tab title updates live as the user types.
    var title: String {
        let firstNonEmptyLine = body
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        return firstNonEmptyLine ?? "Untitled"
    }
}
