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

            HStack {
                Button("New Scan") { viewModel.reset() }
                    .buttonStyle(.plain)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 10)
        }
    }

    // MARK: - Scan controls

    private var scanControls: some View {
        VStack(alignment: .leading, spacing: 20) {
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

            HStack(spacing: 10) {
                Button(viewModel.beforeSnapshot == nil ? "Shoot Before" : "Re-shoot Before") {
                    Task { await viewModel.shootBefore() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isScanning)

                Button("Shoot After") {
                    Task { await viewModel.shootAfter() }
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.canShootAfter)
            }
            .controlSize(.large)

            if let error = viewModel.scanError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
            Text("Not ready yet? Hit Re-shoot Before to retake.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
        }
    }
}
