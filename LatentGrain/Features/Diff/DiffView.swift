import SwiftUI
import AppKit

// MARK: - DiffView
//
// Full layout (top to bottom):
//
//   ┌─────────────────────────────────────────┐
//   │  [polaroid]  Before  42 items  10:00    │  ← polaroid header (showPolaroids only)
//   │              After   44 items  10:30    │    18pt top / 14pt bottom padding
//   │              [+2] [-1]                  │    16pt horizontal inset
//   ├─────────────────────────────────────────┤  ← Divider
//   │  [ Search findings… ]                   │  ← search bar (revealed state only)
//   ├─────────────────────────────────────────┤
//   │  ADDED                                  │
//   │  ┌─────────────────────────────────┐    │
//   │  │ com.example.agent.plist         │    │  ← ItemRow card (glass surface)
//   │  │ /path/to/binary           [open]│    │
//   │  └─────────────────────────────────┘    │
//   │  REMOVED  …                             │
//   │  ──────────────────────────────────     │  ← Divider before All Items
//   │  ALL ITEMS (44)                         │
//   │    User Agents                          │
//   │    ┌───────────────────────────────┐    │
//   │    │ com.example.plist       [open]│    │
//   │    └───────────────────────────────┘    │
//   └─────────────────────────────────────────┘
//                                40pt fade overlay at bottom edge

// MARK: - Timeline deep-link notification

extension Notification.Name {
    /// Posted to ask AppDelegate to open (or front) the timeline window.
    static let openTimelineWindow = Notification.Name("LatentGrain.openTimelineWindow")
    /// Posted when the diff view wants the timeline to select a specific record.
    /// userInfo key: "recordID" → UUID
    static let selectTimelineRecord = Notification.Name("LatentGrain.selectTimelineRecord")
    /// Posted when the diff view wants the timeline to switch to the Sources tab.
    /// userInfo key: "location" → PersistenceLocation.rawValue (String)
    static let selectTimelineSource = Notification.Name("LatentGrain.selectTimelineSource")
}

// MARK: - Environment key for timeline action

private struct TimelineActionKey: EnvironmentKey {
    static let defaultValue: () -> Void = {
        NotificationCenter.default.post(name: .openTimelineWindow, object: nil)
    }
}

extension EnvironmentValues {
    fileprivate var timelineAction: () -> Void {
        get { self[TimelineActionKey.self] }
        set { self[TimelineActionKey.self] = newValue }
    }
}

// MARK: - Section offset tracking

/// Collects each source section's minY relative to the scroll container,
/// used to determine which section is currently in view.
private struct SectionOffsetKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

// MARK: - DiffView

struct DiffView: View {

    // The result of comparing two snapshots — drives all displayed content
    let diff: PersistenceDiff
    // Set to false in contexts (e.g. Timeline) that supply their own header
    var showPolaroids: Bool = true
    // When set, the "timeline" button on each item card deep-links to this record
    var timelineRecordID: UUID? = nil

    // Current text in the search bar; filters items in the revealed results list
    @State private var searchText = ""
    // Raw value of the source section currently visible in the scroll area
    @State private var currentSourceID: String? = nil

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

    /// Source sections that have at least one item matching the current search.
    /// Pre-filtered so both the scroll list and the index strip share the same set.
    private var visibleLocations: [(location: PersistenceLocation, items: [PersistenceItem])] {
        diff.after.groupedByLocation
            .sorted(by: { $0.key.rawValue < $1.key.rawValue })
            .compactMap { location, items in
                let filtered = items.filter(matches)
                return filtered.isEmpty ? nil : (location, filtered)
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Decorative polaroid + before/after stats — hidden when a parent supplies its own header
            if showPolaroids {
                polaroid
                    .padding(.top, 18)
                    .padding(.bottom, 8)

            }

            resultsArea
                .frame(maxHeight: .infinity)
        }
        .environment(\.timelineAction, {
            NotificationCenter.default.post(name: .openTimelineWindow, object: nil)
            if let id = timelineRecordID {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    NotificationCenter.default.post(
                        name: .selectTimelineRecord,
                        object: nil,
                        userInfo: ["recordID": id]
                    )
                }
            }
        })
    }

    // Header row: BEFORE stats on the left, polaroid in the centre, AFTER stats on the right.
    private var polaroid: some View {
        VStack(spacing: 18) {
            HStack(alignment: .center, spacing: 0) {
                statColumn(
                    label: "BEFORE",
                    value: diff.before.timestamp.formatted(.dateTime.hour().minute()),
                    detail: "\(diff.before.itemCount) items"
                )
                .frame(maxWidth: .infinity)

                PolaroidCardView()
                    .padding(.horizontal, 14)

                statColumn(
                    label: "AFTER",
                    value: diff.after.timestamp.formatted(.dateTime.hour().minute()),
                    detail: "\(diff.after.itemCount) items"
                )
                .frame(maxWidth: .infinity)
            }

            if diff.isEmpty {
                Text("no changes found")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.green.opacity(0.8))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.09))
                    .overlay(Capsule().strokeBorder(Color.green.opacity(0.2), lineWidth: 1))
                    .clipShape(Capsule())
            } else {
                let total = diff.added.count + diff.removed.count + diff.modified.count
                Text("\(total) finding\(total == 1 ? "" : "s")")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.accentColor.opacity(0.9))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.09))
                    .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.4), lineWidth: 1))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
    }

    private func statColumn(label: String, value: String, detail: String?, valueColor: Color = .secondary, detailColor: Color = .secondary) -> some View {
        VStack(alignment: .center, spacing: 2) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.72))
                .kerning(0.5)
                .textCase(.uppercase)

            Text(value)
                .font(.system(size: 11))
                .foregroundStyle(valueColor)

            if let detail {
                Text(detail)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(detailColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private var resultsArea: some View {
        VStack(spacing: 0) {
            SearchBar(
                text: $searchText,
                placeholder: "Search...",
                suggestions: suggestions
            )
            .padding(.horizontal, 22)
            .padding(.top, diff.isEmpty ? 0 : 2)

            ZStack(alignment: .bottom) {
                ScrollViewReader { proxy in
                    ZStack(alignment: .trailing) {
                        ScrollView(.vertical, showsIndicators: false) {
                            LazyVStack(alignment: .leading, spacing: 0) {

                                // Findings (added / removed / changed)
                                if !diff.isEmpty {
                                    changesSection
                                        .padding(.horizontal, 22)
                                        .padding(.top, 32)
                                        .padding(.bottom, 12)
                                }

                                // "All Items" label
                                let allFiltered = diff.after.items.filter(matches)
                                if diff.after.itemCount > 0 {
                                    Text(searchText.isEmpty
                                         ? "All Items (\(diff.after.itemCount))"
                                         : "Results (\(allFiltered.count))")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 22)
                                        .padding(.top, diff.isEmpty ? 22 : 4)
                                        .padding(.bottom, 8)
                                }

                                // One group per source — headers are inline (not sticky)
                                ForEach(visibleLocations, id: \.location.rawValue) { entry in
                                    VStack(alignment: .leading, spacing: 0) {

                                        // Invisible anchor for scroll-to + position tracking
                                        Color.clear.frame(height: 0)
                                            .id(entry.location.rawValue)
                                            .background(
                                                GeometryReader { geo in
                                                    Color.clear.preference(
                                                        key: SectionOffsetKey.self,
                                                        value: [entry.location.rawValue: geo.frame(in: .named("diffScroll")).minY]
                                                    )
                                                }
                                            )

                                        // Inline source header
                                        HStack(spacing: 8) {
                                            RoundedRectangle(cornerRadius: 1)
                                                .fill(entry.location.badgeColor)
                                                .frame(width: 2, height: 14)
                                            Text(entry.location.displayName)
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundStyle(entry.location.badgeColor.opacity(0.65))
                                                .fixedSize()
                                            Rectangle()
                                                .fill(entry.location.badgeColor.opacity(0.18))
                                                .frame(height: 0.5)
                                                .frame(maxWidth: .infinity)
                                            Text("\(entry.items.count)")
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundStyle(entry.location.badgeColor.opacity(0.7))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(entry.location.badgeColor.opacity(0.10))
                                                .clipShape(Capsule())
                                        }
                                        .padding(.horizontal, 22)
                                        .padding(.top, 18)
                                        .padding(.bottom, 8)

                                        // Items
                                        VStack(alignment: .leading, spacing: 14) {
                                            ForEach(entry.items) { item in
                                                ItemRow(item: item, showLocationBadge: false)
                                                    .environment(\.timelineAction, {
                                                        let loc = entry.location.rawValue
                                                        NotificationCenter.default.post(name: .openTimelineWindow, object: nil)
                                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                                            NotificationCenter.default.post(
                                                                name: .selectTimelineSource,
                                                                object: nil,
                                                                userInfo: ["location": loc]
                                                            )
                                                        }
                                                    })
                                            }
                                        }
                                        .padding(.horizontal, 22)
                                        .padding(.top, 2)
                                        .padding(.bottom, 24)
                                    }
                                }
                            }
                            // Extra space so the last section can always scroll its header to the top
                            Color.clear.frame(height: 320)
                        }
                        .coordinateSpace(name: "diffScroll")
                        .onPreferenceChange(SectionOffsetKey.self) { offsets in
                            // Current section = the one whose header is nearest the top from above
                            let threshold: CGFloat = 60
                            if let hit = offsets.filter({ $0.value <= threshold }).max(by: { $0.value < $1.value }) {
                                currentSourceID = hit.key
                            } else {
                                // Haven't scrolled into any section yet — highlight the first
                                currentSourceID = offsets.min(by: { $0.value < $1.value })?.key
                            }
                        }

                        // Source index strip — coloured dots, one per visible source
                        VStack(spacing: 7) {
                            ForEach(visibleLocations, id: \.location.rawValue) { entry in
                                let isActive = currentSourceID == entry.location.rawValue
                                Button {
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        proxy.scrollTo(entry.location.rawValue, anchor: .top)
                                    }
                                } label: {
                                    Circle()
                                        .fill(entry.location.badgeColor.opacity(isActive ? 0.85 : 0.18))
                                        .frame(width: isActive ? 7 : 5, height: isActive ? 7 : 5)
                                        .animation(.easeInOut(duration: 0.18), value: isActive)
                                }
                                .buttonStyle(.plain)
                                .focusable(false)
                            }
                        }
                        .padding(.trailing, 8)
                        .frame(maxHeight: .infinity)
                    }
                }
            }
            .mask(
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: 32)
                    Rectangle()
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 40)
                }
            )
        }
    }

    // MARK: - Changes section

    // Grouped lists for everything that was added, removed, or modified
    private var changesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Apply current search filter before rendering each group
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

    // Coloured section header + a card per item — mirrors the timeline detail pane pattern
    private func itemGroup(title: String, items: [PersistenceItem], accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section title coloured to match the change type — same as timeline detail pane
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(accent.opacity(0.85))

            VStack(alignment: .leading, spacing: 14) {
                ForEach(items) { item in
                    ItemRow(item: item, changeIndicatorColor: accent)
                }
            }
        }
    }

}

// MARK: - ItemRow
//
// Glass card showing one persistence item. Visual structure:
//
//   ┌─────────────────────────────────────────────┐
//   │ [badge: User Agents] [runs at login]         │  ← coloured capsule badges, 10pt
//   │ com.example.LaunchAgent.plist                │  ← filename, 13pt medium
//   │ 🔹 MyApp                                     │  ← attribution (14×14pt icon + 12pt name)
//   │ /Library/Application Support/…/binary        │  ← program path, 11pt, middle-truncated
//   ├─────────────────────────────────────────────┤  ← 0.5pt hairline, white 8%
//   │ 📂 open                                      │  ← action bar, black 20% bg, 8pt v-pad
//   └─────────────────────────────────────────────┘
//
// Outer card: rightPaneCardSurface (white 3% bg, white 8% stroke) + orangeHoverShimmer.
// No accent colour in the card itself — accent only appears in the section title above.

struct ItemRow: View {

    // The persistence item to display
    let item: PersistenceItem
    // Hide when items are already grouped under a location header
    var showLocationBadge: Bool = true
    // When set, shows a small coloured dot on the trailing edge indicating change type
    var changeIndicatorColor: Color? = nil

    // Toggled in Settings — shows the attributed app icon and name below the filename
    @AppStorage("showAttribution") private var showAttribution = true
    @Environment(\.timelineAction) private var timelineAction


    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Main content ───────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 6) {
                // Type pill always shown; behavioural flags are additive alongside it.
                HStack(spacing: 5) {
                    if showLocationBadge {
                        locationBadge(item.location)
                    } else {
                        typeBadge(item.location)
                    }
                    if item.location == .configurationProfiles && item.runAtLoad == true {
                        badge("managed")
                    } else if item.runAtLoad == true {
                        badge("runs at login")
                    } else if item.keepAlive == true {
                        badge("keeps running")
                    }
                    if let color = changeIndicatorColor {
                        Spacer()
                        Circle()
                            .fill(color.opacity(0.85))
                            .frame(width: 7, height: 7)
                    }
                }

                // Filename — allowed to wrap so long names are always fully readable
                Text(item.filename)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                // App icon + name that installed this item — only shown when attribution is known
                if showAttribution, let attribution = item.attribution {
                    HStack(spacing: 4) {
                        AsyncAppIcon(paths: [attribution.appBundlePath], size: 14)
                        Text(attribution.appName)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                // Binary path — truncated in the middle so the filename stays readable
                if let program = item.programPath {
                    Text(program)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)

            // ── Action bar ─────────────────────────────────────────────────
            // Dark footer shelf with quick-action buttons (open in Finder, etc.)
            HStack(spacing: 8) {
                Spacer()
                ActionButton(label: "timeline", icon: "waveform.path.ecg", action: timelineAction)
                ActionButton(label: "open", icon: "folder") { revealInFinder() }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(Color.black.opacity(0.20))
            .overlay(alignment: .top) {
                // Hairline separator between content and action bar
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 0.5)
            }
        }
        .rightPaneCardSurface(cornerRadius: 8)
        .orangeHoverShimmer(cornerRadius: 8, opacity: 0.11)
    }

    private func locationBadge(_ location: PersistenceLocation) -> some View {
        let color = location.badgeColor
        return Text(location.shortName)
            .font(.system(size: 11, weight: .medium))
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
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.orange.opacity(0.6))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.orange.opacity(0.07))
            .overlay(
                Capsule().strokeBorder(Color.orange.opacity(0.2), lineWidth: 1)
            )
            .clipShape(Capsule())
    }

    private func typeBadge(_ location: PersistenceLocation) -> some View {
        let color = location.badgeColor
        return Text(location.typeLabel)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(color.opacity(0.7))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.07))
            .overlay(
                Capsule().strokeBorder(color.opacity(0.2), lineWidth: 1)
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

// MARK: - ActionButton

/// A small labelled icon button used in the item action bar.
/// Manages its own hover state so multiple buttons can coexist independently.
private struct ActionButton: View {
    let label: String
    let icon: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(isHovered ? Color.accentColor : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isHovered ? Color.accentColor.opacity(0.12) : Color.clear)
            .clipShape(Capsule())
            .animation(.easeInOut(duration: 0.12), value: isHovered)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { isHovered = $0 }
    }
}

// MARK: - SnapshotComparePanel
//
// Two stacked snapshot rows to the right of the polaroid:
//
//   Before   42 items   10:00 AM     ← row 1
//   After    44 items   10:30 AM     ← row 2
//
// Label column is fixed-width so counts and timestamps align vertically.

struct SnapshotComparePanel: View {
    // The diff whose before/after snapshots are displayed side-by-side
    let diff: PersistenceDiff

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            snapshotRow("Before", snapshot: diff.before)
            snapshotRow("After",  snapshot: diff.after)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // "Before   42 items   10:00 AM"
    // Label is fixed 38pt so counts line up across both rows
    private func snapshotRow(_ title: String, snapshot: PersistenceSnapshot) -> some View {
        HStack(alignment: .center, spacing: 6) {
            Text(snapshot.timestamp.formatted(.dateTime.hour().minute()))
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .frame(width: 38, alignment: .leading)
            
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .frame(width: 48, alignment: .leading)
            
            Text("\(snapshot.itemCount) items")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.06))
                .clipShape(Capsule())
        }
    }

}

// MARK: - Location badge color

extension PersistenceLocation {
    var badgeColor: Color {
        switch self {
        case .userLaunchAgents:        return Color(red: 0.85, green: 0.65, blue: 0.0)
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

// MARK: - Preview helpers

#if DEBUG
extension PersistenceItem {
    static func mock(
        filename: String = "com.example.agent.plist",
        location: PersistenceLocation = .userLaunchAgents,
        label: String? = "com.example.Agent",
        programPath: String? = "/Library/Application Support/Example/agent",
        runAtLoad: Bool? = true
    ) -> PersistenceItem {
        PersistenceItem(
            id: UUID(),
            filename: filename,
            fullPath: location.resolvedPath + "/" + filename,
            location: location,
            modificationDate: Date(),
            fileSize: 1024,
            contentsHash: UUID().uuidString,
            label: label,
            programPath: programPath,
            runAtLoad: runAtLoad,
            keepAlive: nil,
            attribution: nil
        )
    }
}

extension PersistenceSnapshot {
    static func mock(items: [PersistenceItem] = [], date: Date = Date()) -> PersistenceSnapshot {
        PersistenceSnapshot(
            id: UUID(),
            timestamp: date,
            label: "Mock snapshot",
            items: items,
            snapshotHash: UUID().uuidString
        )
    }
}

extension PersistenceDiff {
    static func mock(
        added: [PersistenceItem] = [],
        removed: [PersistenceItem] = [],
        modified: [(before: PersistenceItem, after: PersistenceItem)] = []
    ) -> PersistenceDiff {
        let beforeItems = removed + modified.map(\.before)
        let afterItems  = added  + modified.map(\.after)
        return PersistenceDiff(
            id: UUID(),
            before: .mock(items: beforeItems, date: Date().addingTimeInterval(-300)),
            after:  .mock(items: afterItems,  date: Date()),
            added: added,
            removed: removed,
            modified: modified
        )
    }
}
#endif

// MARK: - Component Previews

#if DEBUG
#Preview("ItemRow — added", traits: .fixedLayout(width: 320, height: 80)) {
    ItemRow(item: .mock())
        .padding(12)
        .preferredColorScheme(.dark)
}

#Preview("ItemRow — removed", traits: .fixedLayout(width: 320, height: 80)) {
    ItemRow(item: .mock(filename: "com.old.daemon.plist", location: .systemLaunchDaemons))
        .padding(12)
        .preferredColorScheme(.dark)
}

#Preview("SnapshotComparePanel", traits: .fixedLayout(width: 240, height: 80)) {
    SnapshotComparePanel(diff: .mock(added: [.mock(), .mock(filename: "com.example.helper.plist")]))
        .padding(12)
        .preferredColorScheme(.dark)
}

// MARK: - Full view previews

#Preview("DiffView — with changes") {
    DiffView(
        diff: .mock(
            added: [.mock(), .mock(filename: "com.example.helper.plist")],
            removed: [.mock(filename: "com.old.agent.plist", location: .systemLaunchAgents)]
        )
    )
    .frame(width: 380, height: 500)
    .preferredColorScheme(.dark)
}

#Preview("DiffView — no changes") {
    DiffView(diff: .mock())
        .frame(width: 380, height: 500)
        .preferredColorScheme(.dark)
}
#endif
