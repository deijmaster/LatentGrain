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

        if FDAService.isGranted {
            let btmItems = (try? await scanBTMLocation()) ?? []
            items.append(contentsOf: btmItems)
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

    /// Recursively scans the BTM directory up to 2 levels deep, collecting .plist files.
    private func scanBTMLocation() async throws -> [PersistenceItem] {
        let location = PersistenceLocation.backgroundTaskMgmt
        let rootURL = URL(fileURLWithPath: location.resolvedPath)
        guard FileManager.default.fileExists(atPath: rootURL.path) else { return [] }

        var result: [PersistenceItem] = []

        let level1 = (try? FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        for entry in level1 {
            let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir {
                let level2 = (try? FileManager.default.contentsOfDirectory(
                    at: entry,
                    includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                    options: [.skipsHiddenFiles]
                )) ?? []
                for file in level2 where Self.isScannable(file) {
                    if let item = makeItem(from: file, location: location) {
                        result.append(item)
                    }
                }
            } else if Self.isScannable(entry) {
                if let item = makeItem(from: entry, location: location) {
                    result.append(item)
                }
            }
        }

        return result
    }

    /// Files worth tracking in the BTM directory. Plist + btm (Apple's BTM binary database).
    /// We don't parse .btm contents — the SHA-256 hash changing is the signal that matters.
    private static func isScannable(_ url: URL) -> Bool {
        ["plist", "btm"].contains(url.pathExtension)
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
