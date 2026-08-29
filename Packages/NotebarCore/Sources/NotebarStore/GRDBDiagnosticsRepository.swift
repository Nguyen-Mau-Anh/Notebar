import Foundation
import GRDB
import NotebarCore

/// The GRDB-backed implementation of `DiagnosticsRepository`. Unlike the
/// other repositories, this one is handed the on-disk path directly at
/// construction (`NotebarDatabase` is the only place that already knows
/// it) rather than deriving it itself — there is no column in any table
/// that records where the database file that holds it lives.
public final class GRDBDiagnosticsRepository: DiagnosticsRepository {
    private let dbQueue: DatabaseQueue
    private let path: URL?

    /// - Parameter path: the on-disk database file's location, or `nil` for
    ///   an in-memory database (tests, previews, and `AppDelegate`'s
    ///   degrade-to-in-memory fallback).
    public init(dbQueue: DatabaseQueue, path: URL?) {
        self.dbQueue = dbQueue
        self.path = path
    }

    public func snapshot() throws -> DatabaseDiagnostics {
        let appliedMigrations = try dbQueue.read { db in
            try Migrations.migrator.appliedMigrations(db)
        }
        return DatabaseDiagnostics(
            path: path?.path,
            sizeOnDisk: path.map(Self.sizeOnDisk),
            appliedMigrations: appliedMigrations
        )
    }

    /// The main database file's size plus any `-wal`/`-shm` sidecar files
    /// SQLite may have alongside it, so the reported number matches what
    /// `du` would show for "the database" rather than just the main file.
    /// Any file that doesn't exist (most databases have no sidecar files
    /// most of the time) contributes zero rather than failing the whole
    /// read.
    private static func sizeOnDisk(of url: URL) -> Int {
        let fileManager = FileManager.default
        let candidates = [url.path, url.path + "-wal", url.path + "-shm"]
        return candidates.reduce(0) { total, path in
            let size = (try? fileManager.attributesOfItem(atPath: path))?[.size] as? Int
            return total + (size ?? 0)
        }
    }
}
