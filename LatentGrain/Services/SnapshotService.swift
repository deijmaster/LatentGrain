import Foundation

/// Scans persistence locations and builds `PersistenceSnapshot` objects.
actor SnapshotService {

    // MARK: - Public API

    func createSnapshot(label: String) async throws -> PersistenceSnapshot {
        var items: [PersistenceItem] = []

        for location in PersistenceLocation.allCases where !location.requiresElevation {
            let locationItems = (try? await scanLocation(location)) ?? []
            items.append(contentsOf: locationItems)
        }

        let sorted = items.sorted { $0.fullPath < $1.fullPath }
        let combinedHashes = sorted.map(\.contentsHash).joined()
        let snapshotHash = FileHasher.sha256(of: Data(combinedHashes.utf8))

        return PersistenceSnapshot(
            id: UUID(),
            timestamp: Date(),
            label: label,
            items: sorted,
            snapshotHash: snapshotHash
        )
    }

    // MARK: - Private helpers

    private func scanLocation(_ location: PersistenceLocation) async throws -> [PersistenceItem] {
        let path = location.resolvedPath
        let url = URL(fileURLWithPath: path)

        guard FileManager.default.fileExists(atPath: path) else { return [] }

        let contents = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )

        return contents
            .filter { $0.pathExtension == "plist" }
            .compactMap { makeItem(from: $0, location: location) }
    }

    private func makeItem(from url: URL, location: PersistenceLocation) -> PersistenceItem? {
        guard
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
            let contentsHash = FileHasher.sha256(of: url)
        else { return nil }

        let modDate  = attrs[.modificationDate] as? Date ?? Date()
        let fileSize = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        let info     = PlistParser.parse(at: url)

        return PersistenceItem(
            id: UUID(),
            filename: url.lastPathComponent,
            fullPath: url.path,
            location: location,
            modificationDate: modDate,
            fileSize: fileSize,
            contentsHash: contentsHash,
            label: info.label,
            programPath: info.programPath,
            runAtLoad: info.runAtLoad,
            keepAlive: info.keepAlive
        )
    }
}
