import Foundation

/// Orchestrates snapshot creation, optionally augmenting with privileged-helper data.
actor ScanService {

    private let snapshotService     = SnapshotService()
    private let helperService       = HelperService()
    private let attributionService  = AttributionService()

    // MARK: - Public API

    /// Take a full snapshot. If the privileged helper is available, includes LaunchDaemons.
    func takeSnapshot(label: String) async throws -> PersistenceSnapshot {
        var snapshot = try await snapshotService.createSnapshot(label: label)

        // Augment with privileged locations if helper is connected
        if helperService.isConnected {
            snapshot = try await augmentWithPrivilegedData(snapshot: snapshot)
        }

        // Resolve app attribution for each item (skip when disabled in settings)
        let attributionEnabled = UserDefaults.standard.object(forKey: "showAttribution") as? Bool ?? true
        if attributionEnabled {
            snapshot = await attributionService.attributeSnapshot(snapshot)
        }

        return snapshot
    }

    // MARK: - Private

    private func augmentWithPrivilegedData(snapshot: PersistenceSnapshot) async throws -> PersistenceSnapshot {
        let daemonPaths = try await helperService.scanDaemons()
        let daemonItems: [PersistenceItem] = daemonPaths.compactMap { path in
            let url = URL(fileURLWithPath: path)
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
                  let hash = FileHasher.sha256(of: url) else { return nil }
            let info     = PlistParser.parse(at: url)
            let modDate  = attrs[.modificationDate] as? Date ?? Date()
            let fileSize = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            return PersistenceItem(
                id: UUID(),
                filename: url.lastPathComponent,
                fullPath: path,
                location: .systemLaunchDaemons,
                modificationDate: modDate,
                fileSize: fileSize,
                contentsHash: hash,
                label: info.label,
                programPath: info.programPath,
                runAtLoad: info.runAtLoad,
                keepAlive: info.keepAlive,
                attribution: nil
            )
        }

        let allItems = (snapshot.items + daemonItems).sorted { $0.fullPath < $1.fullPath }
        let combinedHashes = allItems.map(\.contentsHash).joined()
        let newHash = FileHasher.sha256(of: Data(combinedHashes.utf8))

        return PersistenceSnapshot(
            id: snapshot.id,
            timestamp: snapshot.timestamp,
            label: snapshot.label,
            items: allItems,
            snapshotHash: newHash
        )
    }
}
