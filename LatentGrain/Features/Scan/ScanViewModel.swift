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
    @Published var isFDAGranted: Bool = FDAService.isGranted

    // MARK: - Derived

    var canShootAfter: Bool { beforeSnapshot != nil && !isScanning }
    var hasDiff: Bool       { currentDiff != nil }

    /// True when there is a diff the user has not yet revealed — drives the orange dot.
    var hasUnreadDiff: Bool { currentDiff != nil && !isDiffRevealed }

    // MARK: - Dependencies

    private let scanService  = ScanService()
    private let diffService  = DiffService()
    let storageService: StorageService

    init(storageService: StorageService = StorageService()) {
        self.storageService = storageService
    }

    // MARK: - Actions

    func recheckFDA() {
        isFDAGranted = FDAService.isGranted
    }

    func shootBefore() async {
        recheckFDA()
        isScanning = true
        scanError  = nil
        defer { isScanning = false }

        do {
            let snapshot    = try await scanService.takeSnapshot(label: "Before")
            beforeSnapshot  = snapshot
            afterSnapshot   = nil
            currentDiff     = nil
            storageService.clearPendingDiffPair()  // starting fresh — discard any pending watch diff
        } catch {
            scanError = error.localizedDescription
        }
    }

    func shootAfter() async {
        guard let before = beforeSnapshot else { return }
        recheckFDA()
        isScanning = true
        scanError  = nil
        defer { isScanning = false }

        do {
            let snapshot = try await scanService.takeSnapshot(label: "After")
            afterSnapshot = snapshot
            let diff      = diffService.diff(before: before, after: snapshot)
            currentDiff   = diff

            // Persist both snapshots
            storageService.save(snapshot: before)
            storageService.save(snapshot: snapshot)

            // Record this diff in history
            storageService.saveDiffRecord(DiffRecord(
                id:               UUID(),
                beforeSnapshotID: before.id,
                afterSnapshotID:  snapshot.id,
                timestamp:        snapshot.timestamp,
                addedCount:       diff.added.count,
                removedCount:     diff.removed.count,
                modifiedCount:    diff.modified.count,
                source:           "Manual"
            ))
        } catch {
            scanError = error.localizedDescription
        }
    }

    func develop() {
        isDiffRevealed = true
        storageService.clearPendingDiffPair()   // diff has been seen — clear the orange dot
    }

    func reset() {
        beforeSnapshot = nil
        afterSnapshot  = nil
        currentDiff    = nil
        scanError      = nil
        isDiffRevealed = false
        storageService.clearPendingDiffPair()  // user started over — discard pending watch diff
    }

    /// Inject a diff produced by WatchService (not revealed — used internally).
    private func injectWatchDiff(_ diff: PersistenceDiff) {
        beforeSnapshot = diff.before
        afterSnapshot  = diff.after
        currentDiff    = diff
        isDiffRevealed = false
    }

    /// Inject a WatchService diff and immediately reveal results.
    /// Used for auto-scan and notification-tap paths — no "Develop" step.
    func injectAndRevealWatchDiff(_ diff: PersistenceDiff) {
        injectWatchDiff(diff)
        isDiffRevealed = true
        storageService.clearPendingDiffPair()
    }

    /// Called once on launch — restores any watch diff that was detected before the last quit.
    func tryLoadPendingDiff() {
        guard let diff = storageService.reconstructPendingDiff(using: diffService) else { return }
        injectAndRevealWatchDiff(diff)
    }
}
