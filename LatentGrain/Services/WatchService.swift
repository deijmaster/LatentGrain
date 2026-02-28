import Foundation
import CoreServices
import UserNotifications

final class WatchService {
    typealias DiffHandler = (PersistenceDiff) -> Void

    private var stream: FSEventStreamRef?
    private var pendingWorkItem: DispatchWorkItem?
    private(set) var pendingDiff: PersistenceDiff?
    private var lastKnownFDAState: Bool = false
    private var isRunning = false

    /// Timestamp when the stream was last started. Notifications are suppressed
    /// for `graceInterval` seconds after each start to avoid noisy alerts from
    /// boot-time churn or first-install filesystem activity.
    private var streamStartDate: Date = .distantPast
    private let graceInterval: TimeInterval = 60

    private let scanService   = ScanService()
    private let diffService   = DiffService()
    private let storage: StorageService
    private let onDiff: DiffHandler
    /// Returns `true` when the main UI is visible — lets us skip posting
    /// notifications entirely (not just suppress the banner).
    private let isUIVisible: () -> Bool
    private let callbackQueue = DispatchQueue(label: "com.latentgrain.watch", qos: .utility)

    init(storage: StorageService, isUIVisible: @escaping () -> Bool = { false }, onDiff: @escaping DiffHandler) {
        self.storage     = storage
        self.isUIVisible = isUIVisible
        self.onDiff      = onDiff
    }

    deinit {
        // Synchronously drain callbackQueue so no in-flight C callback can
        // fire against freed memory after self is deallocated.
        callbackQueue.sync { stopStream() }
    }

    // MARK: - Public API (idempotent)

    func start() {
        callbackQueue.async { [weak self] in
            guard let self, !self.isRunning else { return }
            self.startStream()
        }
    }

    func stop() {
        callbackQueue.async { [weak self] in
            guard let self, self.isRunning else { return }
            self.stopStream()
        }
    }

    /// Stop + restart with an updated path list (call when FDA state changes).
    func restartWithCurrentFDAState() {
        callbackQueue.async { [weak self] in
            guard let self else { return }
            self.stopStream()
            self.startStream()
        }
    }

    func clearPendingDiff() {
        pendingDiff = nil
    }

    // MARK: - Stream lifecycle (must run on callbackQueue)

    private func startStream() {
        lastKnownFDAState = FDAService.isGranted

        // BTM/TCC paths require FDA; all others are world-readable.
        // Use watchPath (parent dir for single-file locations) and deduplicate.
        let paths = Array(Set(
            PersistenceLocation.allCases
                .filter { !$0.requiresElevation || lastKnownFDAState }
                .map    { $0.watchPath }
        ))

        guard !paths.isEmpty else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let flags: FSEventStreamCreateFlags = UInt32(
            kFSEventStreamCreateFlagUseCFTypes |
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagNoDefer    |
            kFSEventStreamCreateFlagWatchRoot
        )

        guard let newStream = FSEventStreamCreate(
            nil,
            watchCallbackBridge,
            &context,
            paths as CFArray,
            FSEventsGetCurrentEventId(), // only events from NOW — no historical replay
            2.5,                         // FSEvents hardware coalescing window (seconds)
            flags
        ) else { return }

        // Assign before scheduling so the reference is visible to any
        // code that runs after FSEventStreamStart (serial queue guarantees
        // ordering, but explicit assignment order removes all ambiguity).
        stream         = newStream
        isRunning      = true
        streamStartDate = Date()
        FSEventStreamSetDispatchQueue(newStream, callbackQueue)
        FSEventStreamStart(newStream)
    }

    private func stopStream() {
        pendingWorkItem?.cancel()
        pendingWorkItem = nil
        if let s = stream {
            FSEventStreamStop(s)
            FSEventStreamInvalidate(s)
            FSEventStreamRelease(s)
            stream = nil
        }
        isRunning = false
    }

    // MARK: - Event handling (called on callbackQueue)

    fileprivate func didReceiveFSEvents() {
        // Software debounce on top of FSEvents 2.5 s coalescing.
        // Total delay from first event: up to 4 s — catches rapid sequential installs.
        pendingWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.handleFilesystemChange() }
        pendingWorkItem = item
        callbackQueue.asyncAfter(deadline: .now() + 1.5, execute: item)
    }

    private func handleFilesystemChange() {
        guard isRunning else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }

            guard let baseline = self.storage.snapshots.last else {
                // No baseline yet: take a silent first snapshot and save it.
                if let snapshot = try? await self.scanService.takeSnapshot(label: "Auto") {
                    self.storage.save(snapshot: snapshot)
                }
                return
            }

            guard let fresh = try? await self.scanService.takeSnapshot(label: "Auto") else { return }
            let diff = self.diffService.diff(before: baseline, after: fresh)
            guard !diff.isEmpty else { return }

            self.pendingDiff = diff
            self.storage.save(snapshot: fresh)   // becomes the new baseline

            // Persist a DiffRecord so History survives app restarts
            self.storage.saveDiffRecord(DiffRecord(
                id:                UUID(),
                beforeSnapshotID:  baseline.id,
                afterSnapshotID:   fresh.id,
                timestamp:         fresh.timestamp,
                addedCount:        diff.added.count,
                removedCount:      diff.removed.count,
                modifiedCount:     diff.modified.count,
                source:            "Auto",
                affectedLocations: diff.affectedLocationValues
            ))

            // Persist the pending pair so the orange dot survives a restart
            self.storage.savePendingDiffPair(beforeID: baseline.id, afterID: fresh.id)

            // Show the results in the popover unconditionally.
            self.onDiff(diff)

            // Only post a system notification when ALL of:
            // 1. User hasn't disabled notifications
            // 2. The popover isn't already showing (no need to buzz when looking at results)
            // 3. Grace period has elapsed (avoids noisy alerts from boot/install churn)
            let notificationsEnabled = UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true
            let withinGrace = Date().timeIntervalSince(self.streamStartDate) < self.graceInterval
            let uiVisible = self.isUIVisible()

            if notificationsEnabled && !uiVisible && !withinGrace {
                self.postNotification(for: diff)
            }
        }
    }

    // MARK: - Notification

    private func postNotification(for diff: PersistenceDiff) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }

            let n = diff.totalChanges
            let s = n == 1 ? "" : "s"

            let content       = UNMutableNotificationContent()
            content.title     = "\(n) persistence change\(s) detected"
            content.body      = self.summaryString(for: diff)
            content.sound     = .default
            content.userInfo  = ["action": "showDiff"]

            let request = UNNotificationRequest(
                identifier: "com.latentgrain.watchchange.\(UUID())",
                content:    content,
                trigger:    nil
            )
            UNUserNotificationCenter.current().add(request)
        }
    }

    private func summaryString(for diff: PersistenceDiff) -> String {
        var parts: [String] = []

        if !diff.added.isEmpty {
            let grouped = Dictionary(grouping: diff.added, by: \.location)
            for (location, items) in grouped.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                let n = items.count
                let noun = Self.noun(for: location, count: n)
                parts.append("\(n) \(noun) added in \(location.displayName)")
            }
        }
        if !diff.removed.isEmpty {
            let grouped = Dictionary(grouping: diff.removed, by: \.location)
            for (location, items) in grouped.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                let n = items.count
                let noun = Self.noun(for: location, count: n)
                parts.append("\(n) \(noun) removed in \(location.displayName)")
            }
        }
        if !diff.modified.isEmpty {
            let n = diff.modified.count
            parts.append("\(n) item\(n == 1 ? "" : "s") modified")
        }

        return parts.joined(separator: ", ")
    }

    /// Location-aware noun for notification strings.
    private static func noun(for location: PersistenceLocation, count: Int) -> String {
        let singular: String
        switch location {
        case .configurationProfiles: singular = "profile"
        case .userTCC, .systemTCC:   singular = "TCC database"
        default: singular = "agent"
        }
        return count == 1 ? singular : singular + "s"
    }
}

// MARK: - C callback bridge (file scope — no captures, safe as C function pointer)

private let watchCallbackBridge: FSEventStreamCallback = { _, clientCallBackInfo, _, _, _, _ in
    guard let info = clientCallBackInfo else { return }
    let service = Unmanaged<WatchService>.fromOpaque(info).takeUnretainedValue()
    service.didReceiveFSEvents()
}
