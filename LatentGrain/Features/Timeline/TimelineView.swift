import SwiftUI
import AppKit

// MARK: - TimelineView

struct TimelineView: View {

    @EnvironmentObject var storageService: StorageService
    // The scan record the user has tapped in the left list
    @State private var selectedRecordID: UUID? = nil
    // Tracks which rows have slid into view during the entrance animation
    @State private var appearedIndices: Set<Int> = []
    // Controls whether the "Clear All" confirmation dialog is showing
    @State private var showClearAllConfirm = false
    @State private var showSmartDeleteConfirm = false
    @State private var smartDeleteMessage = ""
    @State private var smartDeleteAction: (() -> Void)? = nil
    // Switches the left list into checkbox-select mode
    @State private var isSelecting = false
    // The set of records the user has checked while in select mode
    @State private var selectedIDs: Set<UUID> = []
    // Which top-level tab (Timeline, Sources, Control Zone) is visible
    @State private var dashboardTab: DashboardTab = .timeline
    // Which persistence source is highlighted in the Sources tab
    @State private var selectedSource: PersistenceLocation = .userLaunchAgents
    // Horizontal padding used around the main content area
    private let outerInset: CGFloat = 14
    // Vertical nudge that aligns the detail pane with the top of the list
    private let detailTopAlignOffset: CGFloat = 44
    // Pop-up notice shown after a restore attempt succeeds or fails
    @State private var restoreNotice: RestoreNotice? = nil
    // IDs of items currently being restored so the button shows as busy
    @State private var restoringActionIDs: Set<UUID> = []
    // Turns the "Control Zone" tab orange when a new action has been recorded
    @State private var hasUnseenActions = false
    // Sends disable/quarantine/restore commands to the privileged helper
    private let actionHelperService = HelperService()

    // Data for the pop-up alert shown after a restore action
    private struct RestoreNotice: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    // One clickable crumb in the navigation path shown at the top of the window
    private struct BreadcrumbSegment: Identifiable {
        let id = UUID()
        let title: String
        let action: (() -> Void)?
    }

    // The three top-level sections of the dashboard
    private enum DashboardTab: String, CaseIterable, Identifiable {
        case timeline
        case sources
        case actions

        var id: String { rawValue }

        // Label shown on each tab pill
        var title: String {
            switch self {
            case .timeline: return "Timeline"
            case .sources: return "Sources"
            case .actions: return "Control Zone"
            }
        }
    }

    // All saved scan records, newest first
    private var records: [DiffRecord] {
        storageService.diffRecords.reversed()
    }

    // The record whose detail is showing on the right — defaults to the newest
    private var selectedRecord: DiffRecord? {
        if let selectedRecordID,
           let matched = records.first(where: { $0.id == selectedRecordID }) {
            return matched
        }
        return records.first
    }

    // How many rows the user has checked in select mode
    private var selectedCount: Int { selectedIDs.count }

    var body: some View {
        VStack(spacing: 0) {
            // Top navigation bar with breadcrumb and tab switcher
            header
            // Content area swaps between the three main tabs
            switch dashboardTab {
            case .timeline:
                timelinePane
            case .sources:
                sourcesPane
            case .actions:
                actionsPane
            }
        }
        // Lets the user copy any visible text
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .top) {
            LinearGradient(
                colors: [Color.black.opacity(0.30), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 60)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
        }
        // Subtle dark tinted background behind all content
        .background(Color(red: 0.1, green: 0.12, blue: 0.2).opacity(0.35))
        // Shows a dismissable alert after a restore finishes
        .alert(item: $restoreNotice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("OK"))
            )
        }
        // Auto-selects the first record when the view first appears
        .onAppear {
            if selectedRecordID == nil { selectedRecordID = records.first?.id }
        }
        // Keeps the selection valid if a record gets deleted
        .onChange(of: records.map(\.id)) { _, newIDs in
            if let selectedRecordID, !newIDs.contains(selectedRecordID) {
                self.selectedRecordID = newIDs.first
            } else if self.selectedRecordID == nil {
                self.selectedRecordID = newIDs.first
            }
        }
    }

    // Permanently removes every checked record from the timeline
    private func deleteSelectedRecords() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            for id in selectedIDs {
                storageService.deleteDiffRecord(id: id)
            }
            selectedIDs.removeAll()
            if let selectedRecordID, !records.map(\.id).contains(selectedRecordID) {
                self.selectedRecordID = records.first?.id
            }
            isSelecting = false
        }
    }

    // Checks or unchecks a single row in select mode
    private func toggleSelection(_ id: UUID) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            if selectedIDs.contains(id) {
                selectedIDs.remove(id)
            } else {
                selectedIDs.insert(id)
            }
        }
    }

    // Returns true when a date-separator header should appear above this row
    private func shouldShowDayMarker(for index: Int, in rows: [DiffRecord]) -> Bool {
        guard index > 0 else { return true }
        return !Calendar.current.isDate(rows[index].timestamp, inSameDayAs: rows[index - 1].timestamp)
    }

    // The "Today / Yesterday / Mar 4" label that groups rows by day
    private func dayMarker(for date: Date) -> some View {
        let cal = Calendar.current
        let label: String
        if cal.isDateInToday(date) {
            label = "Today"
        } else if cal.isDateInYesterday(date) {
            label = "Yesterday"
        } else {
            label = date.formatted(.dateTime.year().month(.abbreviated).day())
        }

        return HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    // Bottom toolbar under the left list — shows select/delete controls
    private var leftTimelineToolbar: some View {
        HStack(spacing: 8) {
            if isSelecting {
                // Checks every row in the list
                controlButton("All", tone: .neutral) {
                    selectedIDs = Set(records.map(\.id))
                }
                // Clears all checkmarks without leaving select mode
                controlButton("None", tone: .neutral) {
                    selectedIDs.removeAll()
                }
                // Delete button — dims when nothing is checked
                controlButton("Delete \(selectedCount)", tone: .danger) {
                    deleteSelectedRecords()
                }
                .opacity(selectedCount == 0 ? 0.45 : 1)
                .disabled(selectedCount == 0)
                // Exits select mode and clears all checkmarks
                controlButton("Done", tone: .active) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isSelecting = false
                        selectedIDs.removeAll()
                    }
                }
            } else {
                // Enters checkbox-select mode
                controlButton("Select", tone: .active) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isSelecting = true
                    }
                }
                // Asks for confirmation before wiping the whole timeline
                controlButton("Delete All", tone: .danger) {
                    showClearAllConfirm = true
                }
                // Targeted delete options
                smartDeleteMenu
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // The three visual styles a toolbar button can have
    private enum ControlTone { case neutral, active, danger }

    // Reusable pill-shaped toolbar button that changes colour based on its role
    private func controlButton(_ title: String, tone: ControlTone, action: @escaping () -> Void) -> some View {
        let fg: Color
        let bg: Color
        let stroke: Color
        // Neutral = grey, active = accent blue, danger = red
        switch tone {
        case .neutral:
            fg = .secondary
            bg = Color.white.opacity(0.04)
            stroke = Color.white.opacity(0.10)
        case .active:
            fg = .primary
            bg = Color.accentColor.opacity(0.18)
            stroke = Color.accentColor.opacity(0.28)
        case .danger:
            fg = .red
            bg = Color.red.opacity(0.12)
            stroke = Color.red.opacity(0.20)
        }

        return Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(fg)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(bg)
                .overlay(
                    Capsule().strokeBorder(stroke, lineWidth: 0.6)
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .orangeHoverShimmer(cornerRadius: 999, opacity: 0.11)
    }

    // MARK: - Smart Delete

    private var smartDeleteMenu: some View {
        Menu {
            Section("Older than") {
                Button("7 days")  { confirm("Delete events older than 7 days?")  { deleteOlderThan(days: 7)  } }
                Button("30 days") { confirm("Delete events older than 30 days?") { deleteOlderThan(days: 30) } }
                Button("90 days") { confirm("Delete events older than 90 days?") { deleteOlderThan(days: 90) } }
            }
            Section("By source") {
                Button("Manual scans") { confirm("Delete all manually triggered scans?") { deleteBySource("Manual") } }
                Button("Auto scans")   { confirm("Delete all auto-watch scans?")          { deleteBySource("Auto")   } }
            }
            Section("Keep only recent") {
                Button("Keep 10 most recent") { confirm("Delete all except the 10 most recent events?") { keepRecent(10) } }
                Button("Keep 25 most recent") { confirm("Delete all except the 25 most recent events?") { keepRecent(25) } }
                Button("Keep 50 most recent") { confirm("Delete all except the 50 most recent events?") { keepRecent(50) } }
            }
            Section {
                Button("No-change scans") { confirm("Delete all scans that found no changes?") { deleteNoChange() } }
            }
        } label: {
            Text("Smart Delete")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.04))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.6))
                .clipShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .focusable(false)
    }

    private func confirm(_ message: String, action: @escaping () -> Void) {
        smartDeleteMessage = message
        smartDeleteAction = action
        showSmartDeleteConfirm = true
    }

    private func deleteOlderThan(days: Int) {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        let ids = records.filter { $0.timestamp < cutoff }.map(\.id)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            if let id = selectedRecordID, ids.contains(id) { selectedRecordID = nil }
            ids.forEach { storageService.deleteDiffRecord(id: $0) }
        }
    }

    private func deleteBySource(_ source: String) {
        let ids = records.filter { $0.source == source }.map(\.id)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            if let id = selectedRecordID, ids.contains(id) { selectedRecordID = nil }
            ids.forEach { storageService.deleteDiffRecord(id: $0) }
        }
    }

    private func keepRecent(_ count: Int) {
        let ids = records.sorted { $0.timestamp > $1.timestamp }.dropFirst(count).map(\.id)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            if let id = selectedRecordID, ids.contains(id) { selectedRecordID = nil }
            ids.forEach { storageService.deleteDiffRecord(id: $0) }
        }
    }

    private func deleteNoChange() {
        let ids = records.filter { $0.totalChanges == 0 }.map(\.id)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            if let id = selectedRecordID, ids.contains(id) { selectedRecordID = nil }
            ids.forEach { storageService.deleteDiffRecord(id: $0) }
        }
    }

    // Small checkbox shown to the left of each row in select mode
    private func selectionMarker(isOn: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(isOn ? Color.accentColor.opacity(0.20) : Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(isOn ? Color.accentColor.opacity(0.45) : Color.white.opacity(0.14), lineWidth: 0.8)
                )
                .frame(width: 16, height: 16)
            if isOn {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

    // Slim bar at the top of the right pane showing which record is open
    private func detailContextHeader(for record: DiffRecord) -> some View {
        let isAuto = record.source == "Auto"
        let frameID = record.id.uuidString.prefix(4).uppercased()

        return HStack(spacing: 8) {
            // AUTO or SCAN badge
            Text(isAuto ? "AUTO" : "SCAN")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
            // Short unique ID for this record
            Text("#\(frameID)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
            // Exact timestamp of the scan
            Text(record.timestamp.formatted(.iso8601.year().month().day().dateSeparator(.dash).time(includingFractionalSeconds: false).timeSeparator(.colon)))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer()
            // "Selected on timeline" hint shown when the record has findings
            if !record.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 9, weight: .semibold))
                    Text("selected on timeline")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.04))
                .overlay(
                    Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                )
                .clipShape(Capsule())
            }
        }
        .padding(.horizontal, TimelineTheme.rightPaneHorizontalInset)
        .padding(.vertical, 8)
    }

    // The main two-column layout: scan list on the left, detail on the right
    private var timelinePane: some View {
        Group {
            if records.isEmpty {
                emptyState
            } else {
                HStack(spacing: 0) {
                    // Left column: scrollable list of past scans
                    VStack(spacing: 0) {
                        ScrollView(.vertical, showsIndicators: true) {
                            LazyVStack(spacing: 0) {
                                ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                                    VStack(spacing: 0) {
                                        // Date separator shown whenever the day changes
                                        if shouldShowDayMarker(for: index, in: records) {
                                            dayMarker(for: record.timestamp)
                                        }

                                        HStack(spacing: 0) {
                                            // Checkbox that slides in from the left when select mode is active
                                            if isSelecting {
                                                Button {
                                                    toggleSelection(record.id)
                                                } label: {
                                                    selectionMarker(isOn: selectedIDs.contains(record.id))
                                                }
                                                .buttonStyle(.plain)
                                                .frame(width: 28)
                                                .padding(.leading, 6)
                                                .transition(.move(edge: .leading).combined(with: .opacity))
                                            }

                                            TimelineRowView(
                                                record: record,
                                                isFirst: index == 0,
                                                isLast: index == records.count - 1,
                                                isSelected: !isSelecting && selectedRecord?.id == record.id,
                                                isAppeared: appearedIndices.contains(index),
                                                onSelect: {
                                                    if isSelecting {
                                                        toggleSelection(record.id)
                                                    } else {
                                                        selectedRecordID = record.id
                                                    }
                                                }
                                            )
                                        }
                                    }
                                    // Staggers each row's entrance animation so they cascade in
                                    .onAppear {
                                        Task {
                                            let delay = UInt64(Double(index) * 0.07 * 1_000_000_000)
                                            try? await Task.sleep(nanoseconds: delay)
                                            _ = withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) {
                                                appearedIndices.insert(index)
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(.top, 12)
                            .padding(.bottom, 12)
                        }
                        // Fades top and bottom edges
                        .windowEdgeFades()
                        leftTimelineToolbar
                    }
                    .frame(width: TimelineTheme.leftPaneWidth)

                    // Right column: detail view or the summary dashboard
                    Group {
                        if let record = selectedRecord {
                            VStack(spacing: 0) {
                                detailContextHeader(for: record)
                                DashboardDetailPane(
                                    record: record,
                                    storageService: storageService,
                                    horizontalInset: TimelineTheme.rightPaneHorizontalInset,
                                    topInset: TimelineTheme.rightPaneTopInset,
                                    cardCornerRadius: TimelineTheme.rightPaneCardCorner,
                                    onActionTaken: { hasUnseenActions = true }
                                )
                            }
                            .id(record.id)
                        } else {
                            dashboardOverviewPane
                        }
                    }
                    .frame(minWidth: TimelineTheme.rightPaneMinWidth, maxWidth: .infinity)
                    .padding(.top, detailTopAlignOffset)
                }
            }
        }
        .padding(.horizontal, outerInset)
        .padding(.top, 8)
        .padding(.bottom, outerInset)
    }

    // Right-pane summary shown when no scan with changes is selected
    private var dashboardOverviewPane: some View {
        // Tallies used to populate the stat cards
        let scanCount = records.count
        let autoCount = records.filter { $0.source == "Auto" }.count
        let manualCount = max(0, scanCount - autoCount)
        let totalChanges = records.reduce(0) { $0 + $1.totalChanges }
        let latestChecked = storageService.snapshots.last?.itemCount ?? 0
        let totalSnapshots = storageService.snapshots.count
        let monitoredSources = PersistenceLocation.allCases.count
        let disabledCount = storageService.activePersistenceActions(of: .disabled).count
        let quarantinedCount = storageService.activePersistenceActions(of: .quarantined).count

        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Dashboard Overview")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)

                // Explanatory note when the selected scan was clean
                if let record = selectedRecord, record.isEmpty {
                    Text("Selected event has no findings. Summary metrics are shown below.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                // Two-column grid of stat tiles
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    overviewCard(title: "Total Scans", value: "\(scanCount)", subtitle: "\(manualCount) manual • \(autoCount) auto")
                    overviewCard(title: "Files Checked", value: "\(latestChecked)", subtitle: "latest snapshot")
                    overviewCard(title: "Tracked Changes", value: "\(totalChanges)", subtitle: "across timeline")
                    overviewCard(title: "Snapshots", value: "\(totalSnapshots)", subtitle: "stored frames")
                    overviewCard(title: "Monitored Sources", value: "\(monitoredSources)", subtitle: "persistence locations")
                    overviewCard(title: "Disabled Items", value: "\(disabledCount)", subtitle: "launchctl disabled")
                    overviewCard(title: "Quarantined Items", value: "\(quarantinedCount)", subtitle: "moved to quarantine")
                    overviewCard(
                        title: "Last Scan",
                        value: records.first?.timestamp.formatted(.dateTime.hour().minute()) ?? "—",
                        subtitle: records.first?.timestamp.formatted(.dateTime.year().month(.abbreviated).day()) ?? "no scans yet"
                    )
                }
            }
            .padding(.top, TimelineTheme.rightPaneTopInset)
            .padding(.horizontal, TimelineTheme.rightPaneHorizontalInset)
            .padding(.bottom, 84)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .windowEndFade()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // A single stat tile with a big number, a title, and a subtitle note
    private func overviewCard(title: String, value: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .rightPaneCardSurface(cornerRadius: TimelineTheme.rightPaneCardCorner)
        .orangeHoverShimmer(cornerRadius: TimelineTheme.rightPaneCardCorner, opacity: 0.09)
    }

    // Two-column layout: source list on the left, source details on the right
    private var sourcesPane: some View {
        HStack(spacing: 0) {
            // Left column: list of all monitored persistence locations
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(PersistenceLocation.allCases, id: \.rawValue) { location in
                        // Tapping a card selects it and loads its details on the right
                        Button {
                            selectedSource = location
                        } label: {
                            sourceCard(for: location, isSelected: selectedSource == location)
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                    }
                }
                .padding(.top, 12)
                .padding(.horizontal, 12)
                .padding(.bottom, 84)
            }
            .windowEndFade()
            .frame(width: TimelineTheme.leftPaneWidth)

            // Right column: details for the selected source
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Source title row with a one-line description and Finder button
                    HStack(spacing: 8) {
                        // Name of the selected persistence location
                        Text(selectedSource.displayName)
                            .font(.system(size: 16, weight: .semibold))
                        Spacer()
                        // Short plain-English description of what this location does
                        Text(selectedSourceReferenceText)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                            .lineLimit(2)
                            .frame(maxWidth: 320, alignment: .trailing)
                        // Opens this folder in Finder
                        Button {
                            openPersistenceSource(selectedSource)
                        } label: {
                            Image(systemName: "folder")
                                .font(.system(size: 13, weight: .semibold))
                                .padding(8)
                                .background(Color.white.opacity(0.04))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 9)
                                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.6)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 9))
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                        .orangeHoverShimmer(cornerRadius: 9, opacity: 0.11)
                        .help("Open source in Finder")
                    }

                    // Card showing path, watch path, type, and access level for this source
                    VStack(alignment: .leading, spacing: 10) {
                        sourceInfoRow("path", value: selectedSource.resolvedPath)
                        sourceInfoRow("watch path", value: selectedSource.watchPath)
                        sourceInfoRow("type", value: selectedSource.isSingleFile ? "single file source" : "directory source")
                        sourceInfoRow("access", value: selectedSource.requiresElevation ? "restricted / elevated" : "readable")
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .rightPaneCardSurface(cornerRadius: TimelineTheme.rightPaneCardCorner)

                    // List of files currently found in this location from the latest snapshot
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Text("Current Items")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                            // Time the snapshot was taken
                            if let latestSnapshot = storageService.snapshots.last {
                                Text(latestSnapshot.timestamp.formatted(.dateTime.hour().minute()))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Text("\(currentSourceItems.count)")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }

                        if currentSourceItems.isEmpty {
                            Text("No items currently captured for this source in the latest snapshot.")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .rightPaneCardSurface(cornerRadius: TimelineTheme.rightPaneCardCorner)
                        } else {
                            ForEach(currentSourceItems.prefix(80), id: \.id) { item in
                                HStack(spacing: 8) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(item.filename)
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Text(item.fullPath)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                    Spacer(minLength: 0)
                                    SourceFolderButton(filePath: item.fullPath)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .rightPaneCardSurface(cornerRadius: TimelineTheme.rightPaneCardCorner)
                                .orangeHoverShimmer(cornerRadius: 10, opacity: 0.11)
                            }
                        }
                    }

                    // Only show events that touched this source
                    let relatedEvents = records.filter { $0.affectedLocations.contains(selectedSource.rawValue) }

                    if relatedEvents.isEmpty {
                        Text("No timeline events mapped to this source yet.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .rightPaneCardSurface(cornerRadius: TimelineTheme.rightPaneCardCorner)
                    } else {
                        // List of past scans that recorded a change in this location
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Recent Events")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)

                            ForEach(Array(relatedEvents.prefix(6)), id: \.id) { record in
                                let isSelected = selectedRecordID == record.id
                                // Tapping jumps to that event in the Timeline tab
                                Button {
                                    selectedRecordID = record.id
                                    dashboardTab = .timeline
                                } label: {
                                    HStack(spacing: 8) {
                                        // Timestamp of the event
                                        Text(record.timestamp.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits).hour(.twoDigits(amPM: .omitted)).minute()))
                                            .font(.system(size: 12, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                        // Quick summary of adds/removes/modifications
                                        Text("\(record.addedCount)+ \(record.removedCount)- \(record.modifiedCount)~")
                                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        Image(systemName: "arrow.right")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .rightPaneCardSurface(selected: isSelected, cornerRadius: TimelineTheme.rightPaneCardCorner)
                                }
                                .buttonStyle(.plain)
                                .focusable(false)
                                .orangeHoverShimmer(cornerRadius: TimelineTheme.rightPaneCardCorner, opacity: 0.11)
                            }
                        }
                    }
                }
                .padding(.horizontal, TimelineTheme.rightPaneHorizontalInset)
                .padding(.top, TimelineTheme.rightPaneTopInset)
                .padding(.bottom, 84)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .windowEndFade()
            .frame(minWidth: TimelineTheme.rightPaneMinWidth, maxWidth: .infinity, alignment: .topLeading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, outerInset)
        .padding(.top, 8)
        .padding(.bottom, outerInset)
    }

    // The "Control Zone" tab — two side-by-side columns for quarantined and disabled items
    private var actionsPane: some View {
        let disabled = storageService.activePersistenceActions(of: .disabled)
        let quarantined = storageService.activePersistenceActions(of: .quarantined)

        return HStack(spacing: 12) {
            // Left column: items that have been moved to quarantine
            actionColumnPane(
                title: "Quarantined",
                count: quarantined.count,
                countSubtitle: "ready to restore",
                recordsTitle: "Quarantined Items",
                records: quarantined,
                emptyText: "No quarantined items.",
                actionTitle: "Restore"
            )
            // Right column: items that have been disabled via launchctl
            actionColumnPane(
                title: "Disabled",
                count: disabled.count,
                countSubtitle: "ready to re-enable",
                recordsTitle: "Disabled Items",
                records: disabled,
                emptyText: "No disabled items.",
                actionTitle: "Re-enable"
            )
        }
        .padding(.horizontal, outerInset)
        .padding(.top, 8)
        .padding(.bottom, outerInset)
    }

    // A single scrollable column showing a stat card followed by the item list
    private func actionColumnPane(
        title: String,
        count: Int,
        countSubtitle: String,
        recordsTitle: String,
        records: [StorageService.PersistenceActionRecord],
        emptyText: String,
        actionTitle: String
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                overviewCard(title: title, value: "\(count)", subtitle: countSubtitle)
                managedActionSection(
                    title: recordsTitle,
                    records: records,
                    emptyText: emptyText,
                    actionTitle: actionTitle
                )
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 84)
        }
        .windowEndFade()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // A clickable card in the sources list showing the location name and path
    private func sourceCard(for location: PersistenceLocation, isSelected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(location.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                // Lock icon for locations that need elevated access
                if location.requiresElevation {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            // Filesystem path shown in small type below the name
            Text(location.resolvedPath)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .leftPaneCardSurface(selected: isSelected, cornerRadius: 10)
        // Dims and desaturates cards that aren't selected so the active one pops
        .opacity(isSelected ? 1.0 : 0.92)
        .saturation(isSelected ? 1.0 : 0.90)
        .orangeHoverShimmer(cornerRadius: 10, opacity: 0.14)
    }

    // A key-value row used inside the source detail info card
    private func sourceInfoRow(_ key: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(key)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // Items found in the selected source in the most recent snapshot, sorted A-Z
    private var currentSourceItems: [PersistenceItem] {
        guard let snapshot = storageService.snapshots.last else { return [] }
        return snapshot.items
            .filter { $0.location == selectedSource }
            .sorted { $0.filename.localizedCaseInsensitiveCompare($1.filename) == .orderedAscending }
    }

    // Short plain-English description of what the selected source monitors
    private var selectedSourceReferenceText: String {
        switch selectedSource {
        case .userLaunchAgents:
            return "Per-user login agents loaded for the current user session."
        case .systemLaunchAgents:
            return "System-wide agents that run in user login contexts."
        case .systemLaunchDaemons:
            return "System daemons that run in the background at the OS level."
        case .systemExtensions:
            return "Installed system extensions that add low-level runtime components."
        case .backgroundTaskMgmt:
            return "Background task policy database used by macOS task management."
        case .configurationProfiles:
            return "Managed profiles that enforce security and system configuration."
        case .userTCC:
            return "Per-user privacy permissions (TCC) for app capability access."
        case .systemTCC:
            return "System-level privacy permissions (TCC) enforced across the host."
        }
    }

    // The scrollable list of managed items (quarantined or disabled) with a restore button on each
    private func managedActionSection(
        title: String,
        records: [StorageService.PersistenceActionRecord],
        emptyText: String,
        actionTitle: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)

            if records.isEmpty {
                Text(emptyText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.02))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                ForEach(records, id: \.id) { record in
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(URL(fileURLWithPath: record.originalPath).lastPathComponent)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.primary)
                            Text(record.label)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text(record.originalPath)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer(minLength: 0)
                        Button(actionTitle) {
                            Task { await restoreActionRecord(record) }
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.orange.opacity(0.10))
                        .overlay(
                            Capsule().strokeBorder(Color.orange.opacity(0.24), lineWidth: 0.6)
                        )
                        .clipShape(Capsule())
                        .orangeHoverShimmer(cornerRadius: 999, opacity: 0.11)
                        .disabled(restoringActionIDs.contains(record.id))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.6)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .orangeHoverShimmer(cornerRadius: 8, opacity: 0.09)
                }
            }
        }
    }

    // Reverses a quarantine or disable action and shows a success/failure alert
    @MainActor
    private func restoreActionRecord(_ record: StorageService.PersistenceActionRecord) async {
        // Prevents double-tapping the restore button
        guard !restoringActionIDs.contains(record.id) else { return }
        restoringActionIDs.insert(record.id)
        defer { restoringActionIDs.remove(record.id) }

        do {
            switch record.kind {
            case .disabled:
                try await actionHelperService.enableItem(
                    path: record.originalPath,
                    label: record.label,
                    domain: record.domain,
                    userUID: record.userUID
                )
            case .quarantined:
                guard let quarantinedPath = record.quarantinePath else {
                    throw NSError(domain: "com.latentgrain.app", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: "Missing quarantine path for restore action."
                    ])
                }
                try await actionHelperService.restoreQuarantinedItem(
                    originalPath: record.originalPath,
                    quarantinedPath: quarantinedPath,
                    label: record.label,
                    domain: record.domain,
                    userUID: record.userUID
                )
            }

            storageService.markPersistenceActionRestored(id: record.id)
            restoreNotice = RestoreNotice(
                title: "Restored",
                message: "\(URL(fileURLWithPath: record.originalPath).lastPathComponent) was restored successfully."
            )
        } catch {
            restoreNotice = RestoreNotice(
                title: "Restore failed",
                message: error.localizedDescription
            )
        }
    }

    // Opens the selected persistence location's folder (or its parent) in Finder
    private func openPersistenceSource(_ location: PersistenceLocation) {
        // Keep Finder navigation constrained to local file URLs derived from
        // known persistence-location paths.
        let path = (location.resolvedPath as NSString).standardizingPath
        if location.isSingleFile {
            if FileManager.default.fileExists(atPath: path) {
                NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
            } else {
                let parent = (path as NSString).deletingLastPathComponent
                if FileManager.default.fileExists(atPath: parent) {
                    NSWorkspace.shared.open(URL(fileURLWithPath: parent, isDirectory: true))
                }
            }
        } else {
            if FileManager.default.fileExists(atPath: path) {
                NSWorkspace.shared.open(URL(fileURLWithPath: path, isDirectory: true))
            }
        }
    }

    // MARK: - Header

    // Top bar containing the breadcrumb path on the left and tab switcher on the right
    private var header: some View {
        // Build the breadcrumb segments for the currently active tab
        let pathTrail: [BreadcrumbSegment]
        switch dashboardTab {
        case .timeline:
            pathTrail = [
                BreadcrumbSegment(title: "Timeline", action: nil)
            ]
        case .sources:
            pathTrail = [
                BreadcrumbSegment(title: "Sources", action: nil)
            ]
        case .actions:
            pathTrail = [
                BreadcrumbSegment(title: "Control Zone", action: nil)
            ]
        }
        // "Persistence Timeline" is always the root crumb and navigates home when tapped
        let trail = [BreadcrumbSegment(title: "Persistence Timeline", action: {
            dashboardTab = .timeline
        })] + pathTrail

        return HStack(spacing: 12) {
            breadcrumbTrail(trail)

            Spacer()
            dashboardTabs

        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .alert("Clear Timeline", isPresented: $showClearAllConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Clear All", role: .destructive) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    selectedRecordID = nil
                    storageService.deleteAllDiffRecords()
                }
            }
        } message: {
            Text("This will remove all timeline events. This cannot be undone.")
        }
        .alert("Smart Delete", isPresented: $showSmartDeleteConfirm) {
            Button("Cancel", role: .cancel) { smartDeleteAction = nil }
            Button("Delete", role: .destructive) {
                smartDeleteAction?()
                smartDeleteAction = nil
            }
        } message: {
            Text(smartDeleteMessage)
        }
    }

    // Renders the "Persistence Timeline › Sources" style navigation path
    private func breadcrumbTrail(_ trail: [BreadcrumbSegment]) -> some View {
        HStack(spacing: 5) {
            ForEach(Array(trail.enumerated()), id: \.offset) { index, segment in
                // Chevron separator between crumbs
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                Group {
                    // Clickable crumb — navigates when tapped
                    if let action = segment.action {
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                action()
                            }
                        } label: {
                            Text(segment.title)
                                .font(.system(size: 12, weight: .semibold))
                                // Last crumb is brighter to show it's the current location
                                .foregroundStyle(index == trail.count - 1 ? .primary : .secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(index == trail.count - 1 ? Color.white.opacity(0.06) : Color.white.opacity(0.025))
                                .overlay(
                                    Capsule().strokeBorder(
                                        index == trail.count - 1 ? Color.white.opacity(0.13) : Color.white.opacity(0.08),
                                        lineWidth: 0.5
                                    )
                                )
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                    } else {
                        // Non-clickable crumb — just a label for the current page
                        Text(segment.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(index == trail.count - 1 ? .primary : .secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(index == trail.count - 1 ? Color.white.opacity(0.06) : Color.white.opacity(0.025))
                            .overlay(
                                Capsule().strokeBorder(
                                    index == trail.count - 1 ? Color.white.opacity(0.13) : Color.white.opacity(0.08),
                                    lineWidth: 0.5
                                )
                            )
                            .clipShape(Capsule())
                    }
                }
                .orangeHoverShimmer(cornerRadius: 999, opacity: 0.10)
            }
        }
    }

    // The three pill-shaped tab buttons in the top-right corner of the header
    private var dashboardTabs: some View {
        HStack(spacing: 6) {
            ForEach(DashboardTab.allCases) { tab in
                let isActive  = dashboardTab == tab
                // Shows an orange alert state on Control Zone when a new action happened
                let hasAlert  = tab == .actions && hasUnseenActions && !isActive

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        dashboardTab = tab
                        // Clears the orange alert dot once the user opens the tab
                        if tab == .actions { hasUnseenActions = false }
                    }
                } label: {
                    Text(tab.title)
                        .font(.system(size: 10, weight: .semibold))
                        // Orange when alerting, full brightness when active, dim otherwise
                        .foregroundStyle(hasAlert ? Color.orange : (isActive ? .primary : .secondary))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            hasAlert
                                ? Color.orange.opacity(0.15)
                                : (isActive ? Color.accentColor.opacity(0.18) : Color.white.opacity(0.03))
                        )
                        .overlay(
                            Capsule().strokeBorder(
                                hasAlert
                                    ? Color.orange.opacity(0.40)
                                    : (isActive ? Color.accentColor.opacity(0.30) : Color.white.opacity(0.10)),
                                lineWidth: 0.6
                            )
                        )
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .orangeHoverShimmer(cornerRadius: 999, opacity: 0.11)
                // Small orange dot in the corner when the tab has an unseen alert
                .overlay(alignment: .topTrailing) {
                    if hasAlert {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 6, height: 6)
                            .offset(x: 3, y: -3)
                            .transition(.scale(scale: 0.1).combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.7), value: hasAlert)
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            VStack(spacing: 4) {
                Text("No detections yet")
                    .font(.system(.body).weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("Shoot before and after an install\nto record your first timeline event.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - TimelineRowView

// One row in the timeline list — a vertical connector line, a dot, and a card
struct TimelineRowView: View {

    let record: DiffRecord
    let isFirst: Bool
    let isLast: Bool
    let isSelected: Bool
    let isAppeared: Bool
    // Called when the user taps the row
    let onSelect: () -> Void

    // Color of the timeline dot — green for clean, blue for added, red for removed
    private var accentColor: Color {
        if record.isEmpty { return .green }
        if record.addedCount > 0 { return .accentColor }
        if record.removedCount > 0 { return .red }
        return .orange
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Leading gutter — vertical line + dot
            gutter
                .frame(width: 24)

            // Card
            TimelineCardView(
                record: record,
                isSelected: isSelected
            )
            .contentShape(Rectangle())
            .onTapGesture(perform: onSelect)
            .padding(.trailing, 14)
            .padding(.vertical, 6)
        }
        .padding(.leading, 10)
        // Fades in and slides up as part of the staggered entrance animation
        .opacity(isAppeared ? 1 : 0)
        .offset(y: isAppeared ? 0 : 12)
    }

    // The vertical connector line and coloured dot on the left edge of each row
    private var gutter: some View {
        VStack(spacing: 0) {
            // Top connector
            Rectangle()
                .fill(isFirst ? .clear : Color.white.opacity(0.15))
                .frame(width: 2, height: 14)

            // Dot
            Circle()
                .fill(accentColor)
                .frame(width: 8, height: 8)

            // Bottom connector
            Rectangle()
                .fill(isLast ? .clear : Color.white.opacity(0.15))
                .frame(width: 2)
                .frame(maxHeight: .infinity)
        }
    }
}

// MARK: - TimelineCardView

struct TimelineCardView: View {

    // The scan result this card displays
    let record: DiffRecord
    // Highlights the card when the user has selected it
    let isSelected: Bool

    // Badge border color — tells you at a glance what kind of change happened
    private var moodColor: Color {
        if record.isEmpty { return .green }
        if record.removedCount > 0 { return .red }
        if record.addedCount > 0 { return .accentColor }
        return .orange
    }

    // One-line summary shown on the card, e.g. "2 added · 1 removed in user agents"
    private var storyText: String {
        if record.isEmpty { return "No persistence delta captured for this frame." }

        var parts: [String] = []
        if record.addedCount > 0 { parts.append("\(record.addedCount) added") }
        if record.removedCount > 0 { parts.append("\(record.removedCount) removed") }
        if record.modifiedCount > 0 { parts.append("\(record.modifiedCount) modified") }

        let scope = record.resolvedLocations.isEmpty
            ? "unknown scope"
            : record.resolvedLocations.map { $0.shortName.lowercased() }.joined(separator: ", ")
        return "\(parts.joined(separator: " · ")) in \(scope)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {

                // Top row: scan type badge + timestamp
                HStack(spacing: 6) {
                    filmBadge
                    Text(record.timestamp.formatted(.iso8601.year().month().day().dateSeparator(.dash).time(includingFractionalSeconds: false).timeSeparator(.colon)))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Spacer()
                }
                .padding(.bottom, 8)

                // Middle row: plain-English summary of what changed
                Text(storyText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .padding(.bottom, 8)

                // Bottom row: action pill ("VIEW GRAINS" or "NO GRAINS"), right-aligned
                HStack(spacing: 6) {
                    Spacer(minLength: 0)
                }

                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    detailsIndicator
                }
                .padding(.top, 7)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 10)
            .transaction { tx in tx.animation = nil }
        }
        // Glass card surface — blue tint when selected, near-invisible when not
        .leftPaneCardSurface(selected: isSelected, cornerRadius: 10)
        // Unselected cards are slightly faded so the selected one stands out
        .opacity(isSelected ? 1.0 : 0.88)
        .saturation(isSelected ? 1.0 : 0.88)
        // Subtle orange glow on hover
        .orangeHoverShimmer(cornerRadius: 10, opacity: 0.11)
        // Small arrow shown on the right edge when the card is selected and has data
        .overlay(alignment: .trailing) {
            if isSelected && !record.isEmpty {
                HStack(spacing: 4) {
                    Rectangle()
                        .fill(Color.white.opacity(0.14))
                        .frame(width: 14, height: 1)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.trailing, -12)
                .allowsHitTesting(false)
            }
        }
    }

    // Small pill at the bottom-right — "VIEW GRAINS" if there's data, "NO GRAINS" if clean
    private var detailsIndicator: some View {
        return HStack(spacing: 4) {
            Text(detailsIndicatorLabel)
                .font(.system(size: 9, weight: .semibold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            if !record.isEmpty {
                Image(systemName: "arrow.right")
                    .font(.system(size: 8, weight: .semibold))
            }
        }
        .foregroundStyle(detailsIndicatorForeground)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(detailsIndicatorBackground)
        .overlay(
            Capsule().strokeBorder(detailsIndicatorStroke, lineWidth: 0.5)
        )
        .clipShape(Capsule())
        .frame(width: detailsIndicatorWidth, alignment: .trailing)
        .orangeHoverShimmer(cornerRadius: 999, opacity: 0.11)
    }

    // Pill label — reflects whether there's anything to show
    private var detailsIndicatorLabel: String {
        record.isEmpty ? "NO GRAINS" : "VIEW GRAINS"
    }

    // Pill text color — green for clean, orange for changes
    private var detailsIndicatorForeground: Color {
        record.isEmpty ? Color.green.opacity(0.86) : Color.orange.opacity(0.92)
    }

    // Pill background — slightly brighter when the card is selected
    private var detailsIndicatorBackground: Color {
        if record.isEmpty { return Color.green.opacity(0.10) }
        return isSelected ? Color.orange.opacity(0.15) : Color.orange.opacity(0.08)
    }

    // Pill border — slightly brighter when the card is selected
    private var detailsIndicatorStroke: Color {
        if record.isEmpty { return Color.green.opacity(0.22) }
        return isSelected ? Color.orange.opacity(0.26) : Color.orange.opacity(0.16)
    }

    // Fixed width keeps all pills the same size regardless of text length
    private var detailsIndicatorWidth: CGFloat {
        record.isEmpty ? 82 : 90
    }

    // Top-left badge showing scan type (AUTO/SCAN) and a short unique ID.
    // Border color matches moodColor to reinforce the change type at a glance.
    private var filmBadge: some View {
        let isAuto = record.source == "Auto"
        let frameID = record.id.uuidString.prefix(4).uppercased()
        return HStack(spacing: 5) {
            Text(isAuto ? "AUTO" : "SCAN")
                .font(.system(size: 10, weight: .bold))
            Text("#\(frameID)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.08))
        .overlay(
            Capsule().strokeBorder(moodColor.opacity(0.35), lineWidth: 0.7)
        )
        .clipShape(Capsule())
    }

}

// MARK: - DashboardDetailPane

// The right pane that shows the full breakdown of what changed in a selected scan
struct DashboardDetailPane: View {
    let record: DiffRecord
    let storageService: StorageService
    let horizontalInset: CGFloat
    let topInset: CGFloat
    let cardCornerRadius: CGFloat
    // Notifies the parent when the user takes an action so the tab badge can update
    var onActionTaken: () -> Void = {}

    // The computed diff loaded for this record
    @State private var diff: PersistenceDiff? = nil
    // True while the diff is being calculated in the background
    @State private var isLoading = true

    // Pop-up shown after a disable or quarantine action completes
    @State private var actionNotice: ActionNotice? = nil
    // Paths of items currently being acted on — disables their buttons while busy
    @State private var actionInFlightPaths: Set<String> = []
    // Sends disable/quarantine commands to the privileged helper
    private let helperService = HelperService()

    // Data for the alert shown after an action succeeds or fails
    private struct ActionNotice: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    // The two actions the user can take on a persistence item
    private enum ItemAction {
        case disable
        case quarantine
    }

    // Everything needed to disable or quarantine a specific launch item
    private struct LaunchActionContext {
        let path: String
        let label: String
        let domain: String
        let userUID: Int
        let quarantineRoot: String
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Event metadata card — always visible, needs no snapshot data
                eventMetaBlock
                // Diff sections — loaded asynchronously from the snapshot pair
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.top, 4)
                } else if let diff {
                    if !diff.added.isEmpty {
                        detailSection("Added", items: diff.added, tone: .green)
                    }
                    if !diff.removed.isEmpty {
                        detailSection("Removed", items: diff.removed, tone: .red)
                    }
                    if !diff.modified.isEmpty {
                        detailSection("Modified", items: diff.modified.map(\.after), tone: .orange)
                    }
                    if diff.added.isEmpty && diff.removed.isEmpty && diff.modified.isEmpty {
                        Text("No changes detected in this scan.")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                } else {
                    Text("Snapshot data no longer available.")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, horizontalInset)
            .padding(.top, topInset)
            .padding(.bottom, 84)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .windowEndFade()
        // Re-loads the diff whenever the selected record changes
        .task(id: record.id) { await loadDiff() }
        .alert(item: $actionNotice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    // The "Event Context" summary card — who, what, when, where at a glance
    private var eventMetaBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Event Context")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.bottom, 2)

            // Key-value rows describing the scan event
            VStack(alignment: .leading, spacing: 5) {
                metaRow("what", value: whatText)
                metaRow(
                    "when",
                    value: record.timestamp.formatted(
                        .iso8601
                            .year()
                            .month()
                            .day()
                            .dateSeparator(.dash)
                            .time(includingFractionalSeconds: false)
                            .timeSeparator(.colon)
                    )
                )
                metaRow("where", value: scopeText)
                metaRow("how", value: record.source == "Auto" ? "auto watch" : "manual scan")
                metaRow("event", value: "#\(record.id.uuidString.prefix(8).uppercased())")
                metaRow("snapshots", value: snapshotText)
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .rightPaneCardSurface(cornerRadius: cardCornerRadius)
    }

    // Human-friendly summary of how many changes were detected
    private var whatText: String {
        let n = record.totalChanges
        return n == 1 ? "1 change detected" : "\(n) changes detected"
    }

    // Comma-separated list of which persistence locations were affected
    private var scopeText: String {
        if record.resolvedLocations.isEmpty { return "unknown" }
        return record.resolvedLocations.map { $0.shortName.lowercased() }.joined(separator: " · ")
    }

    // A single labelled row inside the Event Context card
    private func metaRow(_ key: String, value: String) -> some View {
        HStack(spacing: 10) {
            Text(key)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
    }

    // Shows the before/after snapshot IDs and their item counts for this event
    private var snapshotText: String {
        guard let pair = storageService.snapshotPair(for: record) else {
            return "pair unavailable"
        }
        let beforeID = pair.before.id.uuidString.prefix(6).uppercased()
        let afterID = pair.after.id.uuidString.prefix(6).uppercased()
        return "#\(beforeID) (\(pair.before.itemCount)) -> #\(afterID) (\(pair.after.itemCount))"
    }

    // A labelled group of item cards — "Added", "Removed", or "Modified"
    private func detailSection(_ title: String, items: [PersistenceItem], tone: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(tone.opacity(0.9))
            ForEach(items) { item in
                ItemDetailCard(
                    item: item,
                    cornerRadius: cardCornerRadius,
                    isActioning: actionInFlightPaths.contains(item.fullPath),
                    onQuarantine: itemAction(.quarantine, for: item),
                    onDisable:    itemAction(.disable,    for: item)
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Returns a void closure for the given action, or nil if the item doesn't support it
    private func itemAction(_ action: ItemAction, for item: PersistenceItem) -> (() -> Void)? {
        guard launchActionContext(for: item) != nil else { return nil }
        return { Task { await runItemAction(action, for: item) } }
    }


    // Returns the details needed to disable or quarantine a launch item, or nil if not applicable
    private func launchActionContext(for item: PersistenceItem) -> LaunchActionContext? {
        guard item.fullPath.hasSuffix(".plist") else { return nil }

        let domain: String
        switch item.location {
        case .systemLaunchDaemons, .systemLaunchAgents:
            domain = "system"
        case .userLaunchAgents:
            domain = "gui"
        default:
            return nil
        }

        let cleanedLabel = (item.label ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = URL(fileURLWithPath: item.fullPath).deletingPathExtension().lastPathComponent
        let label = cleanedLabel.isEmpty ? fallback : cleanedLabel
        // Keep quarantine material in a visible, user-owned location.
        let quarantineRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/LatentGrain/Quarantine")
            .path

        return LaunchActionContext(
            path: item.fullPath,
            label: label,
            domain: domain,
            userUID: Int(getuid()),
            quarantineRoot: quarantineRoot
        )
    }

    // Executes a disable or quarantine action on a persistence item and shows the result
    @MainActor
    private func runItemAction(_ action: ItemAction, for item: PersistenceItem) async {
        guard let ctx = launchActionContext(for: item) else {
            actionNotice = ActionNotice(
                title: "Action unavailable",
                message: "This persistence item type does not support disable/quarantine actions."
            )
            return
        }

        // System-domain items (daemons and system-wide agents) require root to
        // modify. The embedded XPC helper runs as the current user, so these
        // operations will fail. Warn upfront rather than silently erroring.
        if ctx.domain == "system" {
            actionNotice = ActionNotice(
                title: "Elevated privileges required",
                message: "Disabling or quarantining system-level items (/Library/LaunchDaemons, /Library/LaunchAgents) requires root access. This is not yet supported — only user launch agents (~Library/LaunchAgents) can be acted on."
            )
            return
        }

        actionInFlightPaths.insert(item.fullPath)
        defer { actionInFlightPaths.remove(item.fullPath) }

        // Suppress WatchService for 20 s so the file-system change we're about
        // to make doesn't trigger a "new persistence item" alert on ourselves.
        storageService.suppressWatchUntil = Date().addingTimeInterval(20)

        do {
            switch action {
            case .disable:
                // Sends the disable command to the XPC helper
                try await helperService.disableItem(
                    path: ctx.path,
                    label: ctx.label,
                    domain: ctx.domain,
                    userUID: ctx.userUID
                )
                // Records the action so it appears in the Control Zone
                storageService.upsertPersistenceAction(
                    originalPath: ctx.path,
                    label: ctx.label,
                    domain: ctx.domain,
                    userUID: ctx.userUID,
                    kind: .disabled,
                    quarantinePath: nil
                )
                actionNotice = ActionNotice(
                    title: "Item disabled",
                    message: "launchctl disable applied to \(item.filename)."
                )
                onActionTaken()
            case .quarantine:
                // Moves the file to the quarantine folder and disables it
                let quarantinedPath = try await helperService.quarantineItem(
                    path: ctx.path,
                    label: ctx.label,
                    domain: ctx.domain,
                    userUID: ctx.userUID,
                    quarantineRoot: ctx.quarantineRoot
                )
                // Records the quarantine so it appears in the Control Zone
                storageService.upsertPersistenceAction(
                    originalPath: ctx.path,
                    label: ctx.label,
                    domain: ctx.domain,
                    userUID: ctx.userUID,
                    kind: .quarantined,
                    quarantinePath: quarantinedPath
                )
                let detail = quarantinedPath ?? "Quarantine move completed."
                actionNotice = ActionNotice(
                    title: "Item quarantined",
                    message: detail
                )
                onActionTaken()
            }
        } catch {
            actionNotice = ActionNotice(
                title: "Action failed",
                message: error.localizedDescription
            )
        }
    }

    // Fetches the before/after snapshot pair and computes the diff in the background
    private func loadDiff() async {
        isLoading = true
        guard let pair = storageService.snapshotPair(for: record) else {
            isLoading = false
            return
        }
        let result = await Task.detached(priority: .userInitiated) {
            DiffService().diff(before: pair.before, after: pair.after)
        }.value
        diff = result
        isLoading = false
    }
}

// Small folder icon button that reveals the given file in Finder
private struct SourceFolderButton: View {
    let filePath: String
    // Tracks hover so the icon brightens and gets an orange border on mouse-over
    @State private var isHovered = false

    var body: some View {
        Button {
            revealInFinder(filePath)
        } label: {
            Image(systemName: "folder")
                .font(.system(size: 12, weight: .semibold))
                // Brighter when hovered
                .foregroundStyle(isHovered ? .primary : .secondary)
                .frame(width: 18, height: 18)
                .padding(4)
                .background(isHovered ? Color.white.opacity(0.08) : Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(
                            // Orange border on hover
                            isHovered ? Color.orange.opacity(0.22) : Color.white.opacity(0.10),
                            lineWidth: 0.6
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .hoverSheen(active: isHovered, opacity: 0.07, cornerRadius: 7)
                // Slight scale-up on hover for a tactile feel
                .scaleEffect(isHovered ? 1.04 : 1.0)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { isHovered = $0 }
        .help("Reveal source in Finder")
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }

    // Opens the file in Finder — falls back to its parent folder if the file is gone
    private func revealInFinder(_ path: String) {
        let normalizedPath = (path as NSString).standardizingPath
        if FileManager.default.fileExists(atPath: normalizedPath) {
            NSWorkspace.shared.selectFile(normalizedPath, inFileViewerRootedAtPath: "")
        } else {
            let parent = (normalizedPath as NSString).deletingLastPathComponent
            if FileManager.default.fileExists(atPath: parent) {
                NSWorkspace.shared.open(URL(fileURLWithPath: parent, isDirectory: true))
            }
        }
    }
}


private extension View {
    // Masks the view so lower content fades out instead of hitting a hard edge.
    func windowEndFade(height: CGFloat = 56) -> some View {
        mask(
            VStack(spacing: 0) {
                Rectangle().fill(Color.black)
                LinearGradient(
                    colors: [Color.black, Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: height)
            }
        )
    }

    // Masks the view so content at the top fades in from the edge.
    func windowStartFade(height: CGFloat = 40) -> some View {
        mask(
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [Color.clear, Color.black],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: height)
                Rectangle().fill(Color.black)
            }
        )
    }

    // Both top and bottom fades combined.
    func windowEdgeFades(topHeight: CGFloat = 40, bottomHeight: CGFloat = 56) -> some View {
        mask(
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: topHeight)
                Rectangle().fill(Color.black)
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: bottomHeight)
            }
        )
    }
}

// MARK: - Preview helpers

#if DEBUG
private extension DiffRecord {
    static func mock(added: Int = 2, removed: Int = 0, modified: Int = 0,
                     source: String = "Manual",
                     locations: [PersistenceLocation] = [.userLaunchAgents]) -> DiffRecord {
        DiffRecord(
            id: UUID(),
            beforeSnapshotID: UUID(),
            afterSnapshotID: UUID(),
            timestamp: Date(),
            addedCount: added,
            removedCount: removed,
            modifiedCount: modified,
            source: source,
            affectedLocations: locations.map(\.rawValue)
        )
    }
}
#endif

// MARK: - ItemDetailCard
//
// A single persistence item card shown in the right pane.
// Pure view — all business logic stays in DashboardDetailPane.

struct ItemDetailCard: View {
    let item: PersistenceItem
    var cornerRadius: CGFloat = TimelineTheme.rightPaneCardCorner
    var isActioning: Bool = false
    var onQuarantine: (() -> Void)? = nil
    var onDisable: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                AsyncAppIcon(paths: resolveIconPaths(for: item), size: 16)
                    .padding(.top, 1)
                Text(item.filename)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if onQuarantine != nil || onDisable != nil {
                    HStack(spacing: 6) {
                        if let onQuarantine { actionPill("Quarantine", recommended: true,  action: onQuarantine) }
                        if let onDisable    { actionPill("Disable",    recommended: false, action: onDisable)    }
                    }
                    .disabled(isActioning)
                }
                SourceFolderButton(filePath: item.fullPath)
            }
            metaRow("source",  value: item.location.displayName)
            metaRow("folder",  value: (item.fullPath as NSString).deletingLastPathComponent)
            if let label = item.label, !label.isEmpty { metaRow("label",   value: label) }
            if let prog  = item.programPath           { metaRow("program", value: prog)  }
            metaRow("file", value: item.fullPath)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .rightPaneCardSurface(cornerRadius: cornerRadius)
    }

    private func metaRow(_ key: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(key)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)
            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func actionPill(_ title: String, recommended: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(recommended ? Color.orange : Color.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 4)
                    .fill(recommended ? Color.orange.opacity(0.12) : Color.white.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(recommended ? Color.orange.opacity(0.3) : Color.white.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .focusable(false)
    }
}

// MARK: - Component Previews

#if DEBUG
#Preview("Item Detail Card", traits: .fixedLayout(width: 480, height: 160)) {
    ItemDetailCard(
        item: .mock(
            filename: "com.example.agent.plist",
            location: .userLaunchAgents,
            label: "com.example.Agent",
            programPath: "/Library/Application Support/Example/agent",
            runAtLoad: true
        ),
        onQuarantine: {},
        onDisable: {}
    )
    .padding(16)
    .preferredColorScheme(.dark)
}

#Preview("Card — added", traits: .fixedLayout(width: 320, height: 90)) {
    TimelineCardView(record: .mock(added: 2), isSelected: false)
        .padding(12)
        .preferredColorScheme(.dark)
}

#Preview("Card — selected", traits: .fixedLayout(width: 320, height: 90)) {
    TimelineCardView(record: .mock(added: 1, removed: 1), isSelected: true)
        .padding(12)
        .preferredColorScheme(.dark)
}

#Preview("Card — clean", traits: .fixedLayout(width: 320, height: 90)) {
    TimelineCardView(record: .mock(added: 0, removed: 0), isSelected: false)
        .padding(12)
        .preferredColorScheme(.dark)
}

#Preview("Row — first", traits: .fixedLayout(width: 360, height: 90)) {
    TimelineRowView(
        record: .mock(added: 3, locations: [.systemLaunchDaemons]),
        isFirst: true, isLast: false,
        isSelected: false, isAppeared: true,
        onSelect: {}
    )
    .preferredColorScheme(.dark)
}

#Preview("Row — selected", traits: .fixedLayout(width: 360, height: 90)) {
    TimelineRowView(
        record: .mock(removed: 1, locations: [.userLaunchAgents, .systemExtensions]),
        isFirst: false, isLast: false,
        isSelected: true, isAppeared: true,
        onSelect: {}
    )
    .preferredColorScheme(.dark)
}

// MARK: - DashboardDetailPane preview

#Preview("Detail Pane") {
    TimelineView()
        .environmentObject(StorageService.preview)
        .frame(width: 1140, height: 740)
        .preferredColorScheme(.dark)
}

// MARK: - Full view preview

#Preview("Timeline — with data") {
    TimelineView()
        .environmentObject(StorageService.preview)
        .frame(width: 1140, height: 740)
        .preferredColorScheme(.dark)
}

#Preview("Timeline — empty") {
    TimelineView()
        .environmentObject(StorageService())
        .frame(width: 1140, height: 740)
        .preferredColorScheme(.dark)
}
#endif
