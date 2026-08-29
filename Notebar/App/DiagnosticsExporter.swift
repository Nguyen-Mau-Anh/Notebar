import AppKit
import OSLog
import UniformTypeIdentifiers
import NotebarCore
import NotebarStore

/// Settings → Data's *Export Diagnostics* button (spec §6.4b): collects the
/// last hour of this app's unified-log entries plus an environment block
/// (app version, macOS version, display geometry, database path/size,
/// applied migrations) and writes one file the user can attach to a report.
///
/// Lives in the app target, not `NotebarCore`/`NotebarStore`: it needs
/// `OSLogStore` (reading the log, not just writing to it) and `NSScreen`/
/// `NSSavePanel`, none of which belong in either package. The environment
/// block itself is built by `DiagnosticsEnvironment` (`NotebarCore`), a pure
/// type with no room for note or task content in its fields — this type
/// only ever fills those fields in and appends the log excerpt as
/// unstructured text alongside it. See `DiagnosticsTests` in
/// `NotebarStoreTests` for the test that leans on that structural
/// guarantee.
enum DiagnosticsExporter {
    /// Presents a save panel and, if the user picks a location, writes the
    /// diagnostics file there. Never writes anywhere without the user
    /// choosing the location first.
    @MainActor
    static func export(model: PanelViewModel) {
        let text = buildReport(model: model)

        let panel = NSSavePanel()
        panel.title = "Export Diagnostics"
        panel.nameFieldStringValue = "Notebar Diagnostics.txt"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
                NotebarLog.app.info("diagnostics exported")
            } catch {
                NotebarLog.app.error("failed to write diagnostics export: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private static func buildReport(model: PanelViewModel) -> String {
        let environment = DiagnosticsEnvironment(
            appVersion: (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "unknown",
            buildNumber: (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "unknown",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            displayGeometry: NSScreen.screens.map(describe),
            database: model.databaseDiagnostics() ?? DatabaseDiagnostics(path: nil, sizeOnDisk: nil, appliedMigrations: [])
        )

        return """
        Notebar Diagnostics
        ====================

        \(environment.renderedText)

        Unified log (subsystem \(NotebarLog.subsystem), last 1 hour)
        --------------------------------------------------------------
        \(unifiedLogSection())
        """
    }

    private static func describe(_ screen: NSScreen) -> String {
        let frame = screen.frame
        return "\(Int(frame.width))x\(Int(frame.height)) @ (\(Int(frame.origin.x)), \(Int(frame.origin.y))), scale \(screen.backingScaleFactor)"
    }

    /// The last hour of this app's own unified-log entries, read via
    /// `OSLogStore(scope: .currentProcessIdentifier)`. That scope reads only
    /// the calling process's own log history and needs no special
    /// entitlement — unlike `.system`, which does — so this works in an
    /// unsandboxed app like this one without asking for anything.
    ///
    /// Falls back to instructions for running `log show` from Terminal if
    /// `OSLogStore` throws for any reason: an honest fallback beats a
    /// diagnostics button that silently produces an empty section (spec
    /// §6.4b).
    private static func unifiedLogSection() -> String {
        do {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let position = store.position(timeIntervalSinceEnd: -3600)
            let predicate = NSPredicate(format: "subsystem == %@", NotebarLog.subsystem)
            let entries = try store.getEntries(at: position, matching: predicate)

            let formatter = ISO8601DateFormatter()
            var lines: [String] = []
            for entry in entries {
                guard let logEntry = entry as? OSLogEntryLog else { continue }
                lines.append("\(formatter.string(from: logEntry.date)) [\(logEntry.category)] \(levelName(logEntry.level)): \(logEntry.composedMessage)")
            }

            return lines.isEmpty
                ? "(no log entries for this subsystem in the last hour)"
                : lines.joined(separator: "\n")
        } catch {
            NotebarLog.app.error("could not read the unified log for export: \(String(describing: error), privacy: .public)")
            return """
            Could not read the unified log from inside the app (\(error)).
            Run this in Terminal instead:
                log show --predicate 'subsystem == "\(NotebarLog.subsystem)"' --last 1h
            """
        }
    }

    private static func levelName(_ level: OSLogEntryLog.Level) -> String {
        switch level {
        case .undefined: return "undefined"
        case .debug: return "debug"
        case .info: return "info"
        case .notice: return "notice"
        case .error: return "error"
        case .fault: return "fault"
        @unknown default: return "unknown"
        }
    }
}
