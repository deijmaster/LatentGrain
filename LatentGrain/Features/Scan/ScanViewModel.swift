import SwiftUI

@MainActor
final class ScanViewModel: ObservableObject {

    // MARK: - Published state

    @Published private(set) var beforeSnapshot: PersistenceSnapshot?
    @Published private(set) var afterSnapshot: PersistenceSnapshot?
    @Published private(set) var currentDiff: PersistenceDiff?
    @Published private(set) var isScanning: Bool = false
    @Published var scanError: String?
    @Published var isDiffRevealed: Bool = false
    @Published var isUpdateAvailable: Bool = false
    @Published var latestTag: String? = nil

    // MARK: - Derived

    var canShootAfter: Bool { beforeSnapshot != nil && !isScanning }
    var hasDiff: Bool       { currentDiff != nil }

    // MARK: - Dependencies

    private let scanService  = ScanService()
    private let diffService  = DiffService()
    let storageService: StorageService

    init(storageService: StorageService = StorageService()) {
        self.storageService = storageService
    }

    // MARK: - Actions

    func shootBefore() async {
        isScanning = true
        scanError  = nil
        defer { isScanning = false }

        do {
            let snapshot    = try await scanService.takeSnapshot(label: "Before")
            beforeSnapshot  = snapshot
            afterSnapshot   = nil
            currentDiff     = nil
        } catch {
            scanError = error.localizedDescription
        }
    }

    func shootAfter() async {
        guard let before = beforeSnapshot else { return }
        isScanning = true
        scanError  = nil
        defer { isScanning = false }

        do {
            let snapshot = try await scanService.takeSnapshot(label: "After")
            afterSnapshot = snapshot
            currentDiff   = diffService.diff(before: before, after: snapshot)

            // Persist both snapshots
            storageService.save(snapshot: before)
            storageService.save(snapshot: snapshot)
        } catch {
            scanError = error.localizedDescription
        }
    }

    func develop() {
        isDiffRevealed = true
    }

    func reset() {
        beforeSnapshot = nil
        afterSnapshot  = nil
        currentDiff    = nil
        scanError      = nil
        isDiffRevealed = false
    }
}
