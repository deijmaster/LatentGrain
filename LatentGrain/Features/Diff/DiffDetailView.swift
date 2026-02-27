import SwiftUI

// MARK: - DiffDetailView

/// Reconstructs a full diff from a DiffRecord's snapshot pair and renders it using DiffView.
struct DiffDetailView: View {

    let record: DiffRecord
    let storageService: StorageService

    @State private var diff: PersistenceDiff? = nil
    @State private var isLoading = true

    var body: some View {
        Group {
            if let diff {
                // Always revealed — user is reviewing history, not discovering for the first time
                DiffView(diff: diff, isRevealed: true, showPolaroids: false) {}
                    .frame(maxHeight: .infinity)
            } else if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("Snapshots no longer available")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("The underlying snapshots may have been pruned.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 260)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { reconstruct() }
    }

    private func reconstruct() {
        guard let pair = storageService.snapshotPair(for: record) else {
            isLoading = false
            return
        }
        diff = DiffService().diff(before: pair.before, after: pair.after)
        isLoading = false
    }
}
