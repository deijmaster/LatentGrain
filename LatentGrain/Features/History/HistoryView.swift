import SwiftUI

/// Snapshot history — premium feature gate in v1.
struct HistoryView: View {

    @EnvironmentObject var storageService: StorageService

    var body: some View {
        VStack(spacing: 0) {
            Text("Snapshot History")
                .font(.system(.headline, design: .monospaced))
                .padding()

            Divider()

            PremiumGateView(feature: "Snapshot History") {
                if storageService.snapshots.isEmpty {
                    emptyState
                } else {
                    snapshotList
                }
            }
        }
        .frame(minWidth: 380, minHeight: 300)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("No snapshots yet")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var snapshotList: some View {
        List(storageService.snapshots.reversed()) { snapshot in
            SnapshotRowView(snapshot: snapshot)
                .swipeActions {
                    Button(role: .destructive) {
                        storageService.delete(snapshot: snapshot)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
        }
        .listStyle(.inset)
    }
}

// MARK: - SnapshotRowView

struct SnapshotRowView: View {

    let snapshot: PersistenceSnapshot

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(snapshot.label)
                    .font(.system(.body, design: .monospaced))
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.caption2)
                    Text(snapshot.timestamp.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(snapshot.itemCount)")
                .font(.system(.title3, design: .monospaced).weight(.semibold))
            Text("items")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - PremiumGateView

/// Wraps content behind a premium paywall overlay (StoreKit integration in Phase 4).
struct PremiumGateView<Content: View>: View {

    let feature: String
    @ViewBuilder let content: () -> Content

    // TODO (Phase 4): replace with @StateObject var storeKit = StoreKitManager()
    @State private var isPremium = false

    var body: some View {
        if isPremium {
            content()
        } else {
            lockedView
        }
    }

    private var lockedView: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.fill")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                Text("\(feature) requires Premium")
                    .font(.system(.body, design: .monospaced).weight(.semibold))
                Text("Unlimited history, PDF/JSON export, and auto-scan — one purchase.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }

            Button("Upgrade to Premium") {
                // TODO (Phase 4): open StoreKit purchase sheet
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
