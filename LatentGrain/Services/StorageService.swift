import Foundation
import Combine

/// Persists `PersistenceSnapshot` objects to disk using JSON.
/// Designed with the same public API that a CoreData backend would expose,
/// making a future migration straightforward.
final class StorageService: ObservableObject {

    @Published private(set) var snapshots: [PersistenceSnapshot] = []

    private let storageURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

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
        self.storageURL = appDir.appendingPathComponent("snapshots.json")
        load()
    }

    // MARK: - Public API

    func save(snapshot: PersistenceSnapshot) {
        // Free tier: keep only the most recent snapshot; premium allows unlimited.
        // Gate is enforced at the call site via FeatureGateManager.
        snapshots.append(snapshot)
        persist()
    }

    func delete(snapshot: PersistenceSnapshot) {
        snapshots.removeAll { $0.id == snapshot.id }
        persist()
    }

    func deleteAll() {
        snapshots.removeAll()
        persist()
    }

    // MARK: - Private

    private func load() {
        guard
            let data = try? Data(contentsOf: storageURL),
            let loaded = try? decoder.decode([PersistenceSnapshot].self, from: data)
        else { return }
        snapshots = loaded
    }

    private func persist() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(snapshots) else { return }
        try? data.write(to: storageURL, options: .atomic)
        // Restrict to owner read/write only — snapshot data is sensitive
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: storageURL.path
        )
    }
}
