import SwiftUI
import AppKit

struct DiffView: View {

    let diff: PersistenceDiff
    let isRevealed: Bool
    var showPolaroids: Bool = true
    let onDevelop: () -> Void

    @State private var searchText = ""

    private func matches(_ item: PersistenceItem) -> Bool {
        guard !searchText.isEmpty else { return true }
        return item.filename.localizedCaseInsensitiveContains(searchText)
            || (item.programPath?.localizedCaseInsensitiveContains(searchText) ?? false)
    }

    /// Autocomplete chips — driven by filenames, location names, and change keywords.
    private var suggestions: [String] {
        guard !searchText.isEmpty else { return [] }
        let q = searchText.lowercased()
        var pool: [String] = []

        // Filenames from all changed items
        let names = Set(
            diff.added.map(\.filename) +
            diff.removed.map(\.filename) +
            diff.modified.map(\.after.filename)
        )
        pool += names.sorted()

        // Location display names
        pool += diff.after.groupedByLocation.keys.map(\.displayName)

        // Change-type keywords
        pool += ["added", "removed", "modified"]

        return Array(Set(
            pool.filter { $0.lowercased().contains(q) && $0.lowercased() != q }
        ))
        .sorted()
        .prefix(6)
        .map { $0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            if showPolaroids {
                polaroidPair
                    .padding(.top, 12)
                    .padding(.bottom, 12)

                Divider()
            }

            resultsArea
                .frame(maxHeight: .infinity)
        }
    }

    private var polaroidPair: some View {
        HStack(alignment: .bottom, spacing: 16) {
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
            VStack(spacing: 0) {
                SearchBar(
                    text: $searchText,
                    placeholder: "Search findings…",
                    suggestions: suggestions
                )
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 6)

                Divider()

                ZStack(alignment: .bottom) {
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 20) {
                            if !diff.isEmpty {
                                changesSection
                            } else if searchText.isEmpty {
                                Text("Nothing changed between snapshots.")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 4)
                            }

                            allItemsSection
                        }
                        .padding(16)
                    }

                    // Fade hint — tells the user there's more to scroll
                    LinearGradient(
                        colors: [.clear, Color(nsColor: .windowBackgroundColor)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 40)
                    .allowsHitTesting(false)
                }
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

            let added    = diff.added.filter(matches)
            let removed  = diff.removed.filter(matches)
            let modified = diff.modified.map(\.after).filter(matches)

            if !added.isEmpty {
                itemGroup(title: "Added", items: added, accent: .green)
            }
            if !removed.isEmpty {
                itemGroup(title: "Removed", items: removed, accent: .red)
            }
            if !modified.isEmpty {
                itemGroup(title: "Changed", items: modified, accent: .orange)
            }
        }
    }

    private func itemGroup(title: String, items: [PersistenceItem], accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .kerning(0.8)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(items) { item in
                    ItemRow(item: item, accent: accent)
                }
            }
        }
    }

    // MARK: - All items section

    private var allItemsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            let allFiltered = diff.after.items.filter(matches)
            Text(searchText.isEmpty
                 ? "All Items (\(diff.after.itemCount))"
                 : "Results (\(allFiltered.count))")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .kerning(0.8)
                .textCase(.uppercase)

            ForEach(
                diff.after.groupedByLocation.sorted(by: { $0.key.rawValue < $1.key.rawValue }),
                id: \.key.rawValue
            ) { location, items in
                let filtered = items.filter(matches)
                if !filtered.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(location.displayName.uppercased())
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .kerning(0.5)

                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(filtered) { item in
                                ItemRow(item: item)
                            }
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
    var accent: Color? = nil

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            // Accent bar
            if let accent {
                Rectangle()
                    .fill(accent)
                    .frame(width: 3)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: 8))
            }

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
                    .focusable(false)
                    .foregroundStyle(isHovered ? Color.accentColor : .secondary)
                    .onHover { isHovered = $0 }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(accent != nil
                ? Color(nsColor: .controlBackgroundColor).opacity(0.6)
                : Color(nsColor: .controlBackgroundColor))
        }
        .background(accent?.opacity(0.08) ?? Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(accent?.opacity(0.2) ?? .clear, lineWidth: 1)
        )
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(Color.orange)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.orange.opacity(0.1))
            .overlay(
                Capsule().strokeBorder(Color.orange.opacity(0.4), lineWidth: 1)
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
