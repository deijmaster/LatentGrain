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
        let q = searchText
        return item.filename.localizedCaseInsensitiveContains(q)
            || (item.label?.localizedCaseInsensitiveContains(q) ?? false)
            || (item.programPath?.localizedCaseInsensitiveContains(q) ?? false)
            || item.location.displayName.localizedCaseInsensitiveContains(q)
            || item.fullPath.localizedCaseInsensitiveContains(q)
            || (item.attribution?.appName.localizedCaseInsensitiveContains(q) ?? false)
            || (item.attribution?.bundleIdentifier?.localizedCaseInsensitiveContains(q) ?? false)
            || item.location.shortName.localizedCaseInsensitiveContains(q)
    }

    /// Autocomplete chips — drawn from every searchable field across the full snapshot.
    private var suggestions: [String] {
        guard !searchText.isEmpty else { return [] }
        let q = searchText.lowercased()
        var pool: [String] = []

        // All items in the after snapshot — filenames, labels, binary names from program paths
        let allItems = diff.after.items
        pool += allItems.map(\.filename)
        pool += allItems.compactMap(\.label)
        pool += allItems.compactMap(\.programPath)
            .map { URL(fileURLWithPath: $0).lastPathComponent }
            .filter { !$0.isEmpty }
        pool += allItems.compactMap(\.attribution?.appName)
        pool += allItems.compactMap(\.attribution?.bundleIdentifier)

        // Labels from changed items (may not be in after snapshot if removed)
        pool += diff.removed.compactMap(\.label)
        pool += diff.removed.map(\.filename)

        // Location display names and short names
        pool += PersistenceLocation.allCases.map(\.displayName)
        pool += PersistenceLocation.allCases.map(\.shortName)

        // Change-type keywords
        pool += ["added", "removed", "modified"]

        return Array(
            Set(pool.filter { !$0.isEmpty && $0.lowercased().contains(q) && $0.lowercased() != q })
                .sorted()
                .prefix(8)
        )
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
                    .focusable(false)
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
                        .padding(.bottom, 40)
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
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .kerning(0.8)

            VStack(alignment: .leading, spacing: 6) {
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

                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(filtered) { item in
                                ItemRow(item: item, showLocationBadge: false)
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
    var showLocationBadge: Bool = true

    @AppStorage("showAttribution") private var showAttribution = true
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
                VStack(alignment: .leading, spacing: 6) {
                    // Badge row — location + behavior
                    if showLocationBadge || item.runAtLoad == true || item.keepAlive == true {
                        HStack(spacing: 5) {
                            if showLocationBadge {
                                locationBadge(item.location)
                            }
                            if item.location == .configurationProfiles && item.runAtLoad == true {
                                badge("managed")
                            } else if item.runAtLoad == true {
                                badge("runs at login")
                            } else if item.keepAlive == true {
                                badge("keeps running")
                            }
                        }
                    }

                    Text(item.filename)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if showAttribution, let attribution = item.attribution {
                        HStack(spacing: 4) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: attribution.appBundlePath))
                                .resizable()
                                .frame(width: 14, height: 14)
                            Text(attribution.appName)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    if let program = item.programPath {
                        Text(program)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer()

                Button("Open") { revealInFinder() }
                    .font(.system(size: 12, weight: .medium))
                    .buttonStyle(.plain)
                    .focusable(false)
                    .foregroundStyle(isHovered ? Color.accentColor : .secondary)
                    .onHover { isHovered = $0 }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
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

    private func locationBadge(_ location: PersistenceLocation) -> some View {
        let color = location.badgeColor
        return Text(location.shortName)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.1))
            .overlay(
                Capsule().strokeBorder(color.opacity(0.3), lineWidth: 1)
            )
            .clipShape(Capsule())
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Color.orange)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.orange.opacity(0.1))
            .overlay(
                Capsule().strokeBorder(Color.orange.opacity(0.4), lineWidth: 1)
            )
            .clipShape(Capsule())
    }

    private func revealInFinder() {
        if item.location == .configurationProfiles {
            // Open System Settings > Profiles pane
            if let url = URL(string: "x-apple.systempreferences:com.apple.Profiles") {
                NSWorkspace.shared.open(url)
            }
            return
        }
        if item.location == .userTCC || item.location == .systemTCC {
            // Open System Settings > Privacy & Security pane (macOS 13+ Ventura scheme)
            if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension") {
                NSWorkspace.shared.open(url)
            }
            return
        }
        let fileURL = URL(fileURLWithPath: item.fullPath)
        if FileManager.default.fileExists(atPath: item.fullPath) {
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: item.location.resolvedPath))
        }
    }
}

// MARK: - Location badge color

extension PersistenceLocation {
    var badgeColor: Color {
        switch self {
        case .userLaunchAgents:        return .blue
        case .systemLaunchAgents:      return .indigo
        case .systemLaunchDaemons:     return .purple
        case .systemExtensions:        return .teal
        case .backgroundTaskMgmt:      return .orange
        case .configurationProfiles:   return .pink
        case .userTCC:                 return .yellow
        case .systemTCC:               return .red
        }
    }
}
