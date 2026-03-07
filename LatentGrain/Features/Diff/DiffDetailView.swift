import SwiftUI
import AppKit

// MARK: - DiffDetailView
//
// Thin wrapper used by the Timeline's right pane to replay a historical scan.
// Loads the two raw snapshots from storage, diffs them on the fly, then hands
// the result to DiffView — always in the revealed state (no Develop step needed
// because the user is reviewing history, not discovering for the first time).
//
// showPolaroids: false — the Timeline supplies its own header context, so the
// decorative polaroid + stats panel at the top of DiffView is suppressed here.
//
// Three visual states:
//   • Loading  — centred small spinner while the diff is being computed
//   • Loaded   — full DiffView (search bar + scrollable item list)
//   • Missing  — centred error state with icon + two lines of explanation text

struct DiffDetailView: View {

    // The historical scan record to replay
    let record: DiffRecord
    // Used to fetch the before/after snapshot pair for this record
    let storageService: StorageService

    // The computed diff — nil until reconstruct() completes
    @State private var diff: PersistenceDiff? = nil
    // True while the diff is being calculated; drives the loading spinner
    @State private var isLoading = true

    var body: some View {
        Group {
            if let diff {
                // Always revealed — user is reviewing history, not discovering for the first time.
                // showPolaroids: false because the Timeline header already provides context.
                DiffView(diff: diff, showPolaroids: false)
                    .frame(maxHeight: .infinity)
            } else if isLoading {
                // Centred spinner — shown while snapshots are fetched and diffed
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Error state — snapshots were deleted or pruned from storage
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("Event no longer available")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { reconstruct() }
    }

    // Fetches the snapshot pair and runs the diff on the calling task's context
    private func reconstruct() {
        guard let pair = storageService.snapshotPair(for: record) else {
            isLoading = false
            return
        }
        diff = DiffService().diff(before: pair.before, after: pair.after)
        isLoading = false
    }
}

// MARK: - Previews

#if DEBUG
// "Loaded" state: DiffDetailView relies on StorageService.snapshotPair(for:) which
// requires real snapshot data on disk — not available in previews. We render DiffView
// directly here to show exactly what DiffDetailView displays once loading completes.
#Preview("DiffDetailView — loaded", traits: .fixedLayout(width: 380, height: 520)) {
    DiffView(
        diff: .mock(
            added: [.mock(), .mock(filename: "com.example.helper.plist")],
            removed: [.mock(filename: "com.old.agent.plist", location: .systemLaunchAgents)]
        ),
        showPolaroids: false
    )
    .preferredColorScheme(.dark)
}

// "Missing" state: shown when the snapshot pair has been pruned from storage.
#Preview("DiffDetailView — missing", traits: .fixedLayout(width: 380, height: 200)) {
    DiffDetailView(
        record: DiffRecord(
            id: UUID(),
            beforeSnapshotID: UUID(),
            afterSnapshotID: UUID(),
            timestamp: Date(),
            addedCount: 2,
            removedCount: 0,
            modifiedCount: 0,
            source: "Manual",
            affectedLocations: []
        ),
        storageService: StorageService()
    )
    .preferredColorScheme(.dark)
}

#endif
