import Foundation

/// The environment half of an Export Diagnostics file (spec §6.4b) — app
/// version, OS version, display geometry, and the database's own
/// `DatabaseDiagnostics` snapshot. Deliberately holds nothing else: every
/// field is a fact about the machine or the store, never a note or task's
/// content, so `renderedText` is safe to hand to anyone regardless of what
/// is actually in the database. The app target gathers these values (they
/// need `Bundle`, `ProcessInfo`, `NSScreen` — none of it AppKit-only except
/// the screen geometry strings, which are already reduced to plain text by
/// the time they reach here) and appends the unified-log excerpt itself,
/// which this type has no part in.
public struct DiagnosticsEnvironment: Equatable, Sendable {
    public var appVersion: String
    public var buildNumber: String
    public var osVersion: String
    /// One line per connected display, already formatted as plain text
    /// (e.g. `"1728x1117 @ (0, 0), scale 2.0"`) — computed by the caller so
    /// this module never needs to know what an `NSScreen` is.
    public var displayGeometry: [String]
    public var database: DatabaseDiagnostics

    public init(
        appVersion: String,
        buildNumber: String,
        osVersion: String,
        displayGeometry: [String],
        database: DatabaseDiagnostics
    ) {
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.osVersion = osVersion
        self.displayGeometry = displayGeometry
        self.database = database
    }

    /// Plain-text rendering for the diagnostics file. No note or task
    /// content ever passes through this type's stored properties, so
    /// nothing here can leak it — see `DiagnosticsTests` for the invariant
    /// this depends on holding at the call site too (the caller must never
    /// pass note content into any of these fields, which none of them have
    /// room for in the first place).
    public var renderedText: String {
        var lines = [
            "App version: \(appVersion) (\(buildNumber))",
            "macOS version: \(osVersion)",
        ]
        if displayGeometry.isEmpty {
            lines.append("Displays: none reported")
        } else {
            lines.append("Displays:")
            lines.append(contentsOf: displayGeometry.map { "  - \($0)" })
        }
        lines.append("Database path: \(database.path ?? "(in-memory — on-disk store could not be opened)")")
        if let size = database.sizeOnDisk {
            lines.append("Database size: \(size) bytes")
        } else {
            lines.append("Database size: unknown")
        }
        if database.appliedMigrations.isEmpty {
            lines.append("Migrations applied: none")
        } else {
            lines.append("Migrations applied: \(database.appliedMigrations.joined(separator: ", "))")
        }
        return lines.joined(separator: "\n")
    }
}
