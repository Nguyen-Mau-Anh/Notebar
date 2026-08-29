import CoreGraphics
import Foundation
import GRDB
import NotebarCore

/// The GRDB implementation of `AppStateRepository`.
public final class GRDBAppStateRepository: AppStateRepository {
    private let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    public func theme() throws -> Theme {
        let stored = try dbQueue.read { db in
            try AppStateRow.fetchOne(db, key: AppStateSchema.themeKey)
        }
        // A missing key (never saved) and an unrecognised value (someone
        // hand-edited the database, or a future build removes a case) both
        // fall back to the default rather than throwing — spec §6.5's
        // control must never be the reason the app won't launch.
        guard let stored, let theme = Theme(rawValue: stored.value) else {
            return .default
        }
        return theme
    }

    public func setTheme(_ theme: Theme) throws {
        try dbQueue.write { db in
            try AppStateRow(key: AppStateSchema.themeKey, value: theme.rawValue).save(db)
        }
    }

    public func edgeDwell() throws -> TimeInterval {
        try numericValue(
            forKey: AppStateSchema.edgeDwellKey,
            default: PanelTiming.edgeDwell,
            range: PanelTiming.edgeDwellRange
        )
    }

    public func setEdgeDwell(_ value: TimeInterval) throws {
        try setNumericValue(value, forKey: AppStateSchema.edgeDwellKey)
    }

    public func exitDwell() throws -> TimeInterval {
        try numericValue(
            forKey: AppStateSchema.exitDwellKey,
            default: PanelTiming.exitDwell,
            range: PanelTiming.exitDwellRange
        )
    }

    public func setExitDwell(_ value: TimeInterval) throws {
        try setNumericValue(value, forKey: AppStateSchema.exitDwellKey)
    }

    public func exitSlop() throws -> CGFloat {
        // Bridged through Double rather than adding a `CGFloat`-generic
        // path: `CGFloat` doesn't conform to `LosslessStringConvertible`,
        // and `ClosedRange<CGFloat>` converts to `ClosedRange<Double>`
        // losslessly (both are IEEE 754 doubles on every Apple platform).
        let range = Double(PanelTiming.exitSlopRange.lowerBound)...Double(PanelTiming.exitSlopRange.upperBound)
        let value = try numericValue(
            forKey: AppStateSchema.exitSlopKey,
            default: Double(PanelTiming.exitSlop),
            range: range
        )
        return CGFloat(value)
    }

    public func setExitSlop(_ value: CGFloat) throws {
        try setNumericValue(Double(value), forKey: AppStateSchema.exitSlopKey)
    }

    /// Shared read path for every Activation timing: a missing key (never
    /// saved) or an unparseable value (someone hand-edited the database to
    /// non-numeric text) both fall back to `defaultValue`, the same
    /// forgiving contract `theme()` uses above. A value that *does* parse
    /// but falls outside `range` is clamped rather than discarded — clamping
    /// on read, not just in the Settings UI, is what keeps a hand-edited
    /// `exitDwell` of 0 from making the panel collapse the instant the
    /// cursor leaves (spec §4.4's hostile behaviour).
    private func numericValue(
        forKey key: String,
        default defaultValue: Double,
        range: ClosedRange<Double>
    ) throws -> Double {
        let stored = try dbQueue.read { db in
            try AppStateRow.fetchOne(db, key: key)
        }
        guard let stored, let value = Double(stored.value) else {
            return defaultValue
        }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    private func setNumericValue(_ value: Double, forKey key: String) throws {
        try dbQueue.write { db in
            try AppStateRow(key: key, value: String(value)).save(db)
        }
    }
}
