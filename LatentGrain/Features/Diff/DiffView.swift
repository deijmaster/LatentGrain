import SwiftUI
import AppKit

struct DiffView: View {

    let diff: PersistenceDiff
    let isRevealed: Bool
    let onDevelop: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            polaroidPair
                .padding(.top, 16)
                .padding(.bottom, 16)

            Divider()

            resultsArea
                .frame(maxHeight: .infinity)
        }
    }

    private var polaroidPair: some View {
        HStack(alignment: .bottom, spacing: 20) {
            PolaroidCardView(title: "BEFORE", snapshot: diff.before, isRevealed: isRevealed)
                .rotationEffect(.degrees(-2))
            PolaroidCardView(title: "AFTER",  snapshot: diff.after,  isRevealed: isRevealed)
                .rotationEffect(.degrees(1.5))
        }
    }

    @ViewBuilder
    private var resultsArea: some View {
        if !isRevealed {
            VStack(spacing: 6) {
                Spacer()
                Button("Develop", action: onDevelop)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                Text("tap to reveal what changed")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
        } else {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 20) {
                    if !diff.isEmpty {
                        changesSection
                    } else {
                        Text("Nothing changed between snapshots.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }

                    allItemsSection
                }
                .padding(16)
            }
        }
    }

    // MARK: - Changes section

    private var changesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if !diff.added.isEmpty {
                    Text("\(diff.added.count) added")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.1))
                        .foregroundStyle(Color.accentColor)
                        .clipShape(Capsule())
                }
                if !diff.removed.isEmpty {
                    Text("\(diff.removed.count) removed")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.1))
                        .foregroundStyle(Color.red)
                        .clipShape(Capsule())
                }
                if !diff.modified.isEmpty {
                    Text("\(diff.modified.count) changed")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.1))
                        .foregroundStyle(Color.orange)
                        .clipShape(Capsule())
                }
            }

            if !diff.added.isEmpty {
                itemGroup(title: "Added", items: diff.added)
            }
            if !diff.removed.isEmpty {
                itemGroup(title: "Removed", items: diff.removed)
            }
            if !diff.modified.isEmpty {
                itemGroup(title: "Changed", items: diff.modified.map(\.after))
            }
        }
    }

    private func itemGroup(title: String, items: [PersistenceItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .kerning(0.8)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(items) { item in
                    ItemRow(item: item)
                }
            }
        }
    }

    // MARK: - All items section

    private var allItemsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            Text("All Items (\(diff.after.itemCount))")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .kerning(0.8)
                .textCase(.uppercase)

            ForEach(
                diff.after.groupedByLocation.sorted(by: { $0.key.rawValue < $1.key.rawValue }),
                id: \.key.rawValue
            ) { location, items in
                VStack(alignment: .leading, spacing: 4) {
                    Text(location.displayName.uppercased())
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .kerning(0.5)

                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(items) { item in
                            ItemRow(item: item)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - ItemRow

struct ItemRow: View {

    let item: PersistenceItem

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.filename)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if item.runAtLoad == true {
                        badge("runs at login")
                    } else if item.keepAlive == true {
                        badge("keeps running")
                    }
                }

                if let program = item.programPath {
                    Text(program)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()

            Button("Open") { revealInFinder() }
                .font(.system(size: 10, weight: .medium))
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .overlay(
                Capsule().strokeBorder(.secondary.opacity(0.3), lineWidth: 1)
            )
            .clipShape(Capsule())
    }

    private func revealInFinder() {
        let fileURL = URL(fileURLWithPath: item.fullPath)
        if FileManager.default.fileExists(atPath: item.fullPath) {
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: item.location.resolvedPath))
        }
    }
}
