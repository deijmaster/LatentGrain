import SwiftUI
import AppKit

struct ScanView: View {

    @ObservedObject var viewModel: ScanViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            locationsStrip
            Divider()

            if let diff = viewModel.currentDiff {
                diffContent(diff)
            } else {
                scanControls
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("LatentGrain")
                    .font(.headline)
                Text("the fine detail of what's hiding")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if viewModel.isScanning {
                Text("Scanning…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Locations strip

    private var locationsStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(Array(PersistenceLocation.allCases.enumerated()), id: \.element.rawValue) { index, location in
                    if index > 0 {
                        Divider().frame(height: 12)
                    }
                    Button {
                        NSWorkspace.shared.open(URL(fileURLWithPath: location.resolvedPath))
                    } label: {
                        Text(location.displayName + (location.requiresElevation ? " (locked)" : ""))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .help(location.resolvedPath)
                }
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 28)
    }

    // MARK: - Diff layout

    private func diffContent(_ diff: PersistenceDiff) -> some View {
        VStack(spacing: 0) {
            DiffView(diff: diff, isRevealed: viewModel.isDiffRevealed) {
                viewModel.develop()
            }
            .frame(maxHeight: .infinity)

            Divider()

            Button("New Scan") { viewModel.reset() }
                .buttonStyle(.plain)
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.vertical, 10)
        }
    }

    // MARK: - Scan controls

    private var scanControls: some View {
        VStack(spacing: 0) {
            // Status area
            VStack(alignment: .leading, spacing: 6) {
                if viewModel.isScanning {
                    Text("Scanning persistence locations…")
                        .font(.body)
                        .foregroundStyle(.secondary)
                } else if let before = viewModel.beforeSnapshot {
                    BeforeReadyView(snapshot: before)
                } else {
                    ReadyToShootView()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)

            Spacer()

            // Action area — one primary action at a time
            VStack(spacing: 8) {
                if viewModel.beforeSnapshot == nil || viewModel.isScanning {
                    Button {
                        Task { await viewModel.shootBefore() }
                    } label: {
                        Text(viewModel.isScanning ? "Scanning…" : "Shoot Before")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(viewModel.isScanning)
                } else {
                    Button {
                        Task { await viewModel.shootAfter() }
                    } label: {
                        Text("Shoot After")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button("Re-shoot Before") {
                        Task { await viewModel.shootBefore() }
                    }
                    .buttonStyle(.plain)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

                if let error = viewModel.scanError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Status sub-views

struct ReadyToShootView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Take a snapshot before installing an app")
                .font(.body.weight(.medium))
            Text("Hit Shoot Before, install your app, then hit Shoot After to see exactly what changed on your Mac.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct BeforeReadyView: View {
    let snapshot: PersistenceSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(snapshot.itemCount)")
                    .font(.title.weight(.semibold).monospacedDigit())
                Text("items found before")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Text("Now install your app, then tap Shoot After.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}
