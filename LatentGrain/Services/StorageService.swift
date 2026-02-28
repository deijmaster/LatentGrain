import Foundation
import Combine

/// Persists `PersistenceSnapshot` and `DiffRecord` objects to disk using JSON.
/// Designed with the same public API that a CoreData backend would expose,
/// making a future migration straightforward.
final class StorageService: ObservableObject {

    @Published private(set) var snapshots:   [PersistenceSnapshot] = []
    @Published private(set) var diffRecords: [DiffRecord]          = []

    /// Non-nil when a watch-detected diff is waiting for the user to view.
    /// Cleared when the diff is revealed (Develop pressed) or manually dismissed.
    private(set) var pendingDiffPair: PendingDiffPairRecord?

    private let storageURL:       URL
    private let diffRecordsURL:   URL
    private let pendingDiffURL:   URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // Thin Codable wrapper — avoids named-tuple Codable limitations
    struct PendingDiffPairRecord: Codable {
        let beforeID: UUID
        let afterID:  UUID
    }

    // MARK: - Init

    init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let appDir = appSupport.appendingPathComponent("LatentGrain", isDirectory: true)
        // 0o700 — only the owner can enter/list this directory
        try? FileManager.default.createDirectory(
            at: appDir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        self.storageURL     = appDir.appendingPathComponent("snapshots.json")
        self.diffRecordsURL = appDir.appendingPathComponent("diff_records.json")
        self.pendingDiffURL = appDir.appendingPathComponent("pending_diff.json")
        load()
    }

    // MARK: - Snapshot API

    func save(snapshot: PersistenceSnapshot) {
        // Free tier: keep only the most recent snapshot; premium allows unlimited.
        // Gate is enforced at the call site via FeatureGateManager.
        snapshots.append(snapshot)
        persistSnapshots()
    }

    func delete(snapshot: PersistenceSnapshot) {
        snapshots.removeAll { $0.id == snapshot.id }
        persistSnapshots()
    }

    func deleteAll() {
        snapshots.removeAll()
        persistSnapshots()
    }

    // MARK: - DiffRecord API

    func saveDiffRecord(_ record: DiffRecord) {
        diffRecords.append(record)
        persistDiffRecords()
    }

    func updateDiffRecord(_ record: DiffRecord) {
        if let idx = diffRecords.firstIndex(where: { $0.id == record.id }) {
            diffRecords[idx] = record
            persistDiffRecords()
        }
    }

    func deleteDiffRecord(id: UUID) {
        diffRecords.removeAll { $0.id == id }
        persistDiffRecords()
    }

    func deleteAllDiffRecords() {
        diffRecords.removeAll()
        persistDiffRecords()
    }

    /// Returns the two snapshots referenced by a DiffRecord, or nil if either has been pruned.
    func snapshotPair(for record: DiffRecord) -> (before: PersistenceSnapshot, after: PersistenceSnapshot)? {
        guard
            let before = snapshots.first(where: { $0.id == record.beforeSnapshotID }),
            let after  = snapshots.first(where: { $0.id == record.afterSnapshotID })
        else { return nil }
        return (before, after)
    }

    // MARK: - Pending diff pair API

    func savePendingDiffPair(beforeID: UUID, afterID: UUID) {
        pendingDiffPair = PendingDiffPairRecord(beforeID: beforeID, afterID: afterID)
        persistPendingDiff()
    }

    func clearPendingDiffPair() {
        pendingDiffPair = nil
        try? FileManager.default.removeItem(at: pendingDiffURL)
    }

    /// Reconstruct a full diff from the pending pair using the supplied DiffService.
    /// Returns nil if either snapshot has been pruned or no pair is recorded.
    func reconstructPendingDiff(using diffService: DiffService) -> PersistenceDiff? {
        guard
            let pair   = pendingDiffPair,
            let before = snapshots.first(where: { $0.id == pair.beforeID }),
            let after  = snapshots.first(where: { $0.id == pair.afterID })
        else { return nil }
        return diffService.diff(before: before, after: after)
    }

    // MARK: - Private — load

    private func load() {
        if let data   = try? Data(contentsOf: storageURL),
           let loaded = try? decoder.decode([PersistenceSnapshot].self, from: data) {
            snapshots = loaded
        }
        if let data    = try? Data(contentsOf: diffRecordsURL),
           let loaded  = try? decoder.decode([DiffRecord].self, from: data) {
            diffRecords = loaded
        }
        if let data   = try? Data(contentsOf: pendingDiffURL),
           let loaded = try? decoder.decode(PendingDiffPairRecord.self, from: data) {
            pendingDiffPair = loaded
        }
    }

    // MARK: - Private — persist

    private func persistSnapshots() {
        write(snapshots, to: storageURL)
    }

    private func persistDiffRecords() {
        write(diffRecords, to: diffRecordsURL)
    }

    private func persistPendingDiff() {
        guard let pair = pendingDiffPair else { return }
        write(pair, to: pendingDiffURL)
    }

    private func write<T: Encodable>(_ value: T, to url: URL) {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(value)
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path
            )
        } catch {
            #if DEBUG
            print("[StorageService] write failed for \(url.lastPathComponent): \(error)")
            #endif
        }
    }
}
