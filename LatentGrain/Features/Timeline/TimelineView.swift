import SwiftUI
import AppKit
import Darwin
import UniformTypeIdentifiers

// MARK: - TimelineView

struct TimelineView: View {

    @EnvironmentObject var storageService: StorageService
    @State private var selectedRecordID: UUID? = nil
    @State private var appearedIndices: Set<Int> = []
    @State private var showClearAllConfirm = false
    @State private var isSelecting = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var dashboardTab: DashboardTab = .timeline
    @State private var selectedSource: PersistenceLocation = .userLaunchAgents
    private let outerInset: CGFloat = 14
    private let detailTopAlignOffset: CGFloat = 44
    @State private var restoreNotice: RestoreNotice? = nil
    @State private var restoringActionIDs: Set<UUID> = []
    private let actionHelperService = HelperService()

    private struct RestoreNotice: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    private struct BreadcrumbSegment: Identifiable {
        let id = UUID()
        let title: String
        let action: (() -> Void)?
    }

    private enum DashboardTab: String, CaseIterable, Identifiable {
        case timeline
        case sources
        case actions

        var id: String { rawValue }

        var title: String {
            switch self {
            case .timeline: return "Timeline"
            case .sources: return "Sources"
            case .actions: return "Control Zone"
            }
        }
    }

    private var records: [DiffRecord] {
        storageService.diffRecords.reversed()
    }

    private var selectedRecord: DiffRecord? {
        if let selectedRecordID,
           let matched = records.first(where: { $0.id == selectedRecordID }) {
            return matched
        }
        return records.first
    }

    private var selectedCount: Int { selectedIDs.count }

    var body: some View {
        VStack(spacing: 0) {
            header
            switch dashboardTab {
            case .timeline:
                timelinePane
            case .sources:
                sourcesPane
            case .actions:
                actionsPane
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert(item: $restoreNotice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .onAppear {
            if selectedRecordID == nil { selectedRecordID = records.first?.id }
        }
        .onChange(of: records.map(\.id)) { _, newIDs in
            if let selectedRecordID, !newIDs.contains(selectedRecordID) {
                self.selectedRecordID = newIDs.first
            } else if self.selectedRecordID == nil {
                self.selectedRecordID = newIDs.first
            }
        }
    }

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

    private func toggleSelection(_ id: UUID) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            if selectedIDs.contains(id) {
                selectedIDs.remove(id)
            } else {
                selectedIDs.insert(id)
            }
        }
    }

    private func shouldShowDayMarker(for index: Int, in rows: [DiffRecord]) -> Bool {
        guard index > 0 else { return true }
        return !Calendar.current.isDate(rows[index].timestamp, inSameDayAs: rows[index - 1].timestamp)
    }

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

    private var leftTimelineToolbar: some View {
        HStack(spacing: 8) {
            if isSelecting {
                controlButton("All", tone: .neutral) {
                    selectedIDs = Set(records.map(\.id))
                }
                controlButton("None", tone: .neutral) {
                    selectedIDs.removeAll()
                }
                controlButton("Delete \(selectedCount)", tone: .danger) {
                    deleteSelectedRecords()
                }
                .opacity(selectedCount == 0 ? 0.45 : 1)
                .disabled(selectedCount == 0)
                controlButton("Done", tone: .active) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isSelecting = false
                        selectedIDs.removeAll()
                    }
                }
            } else {
                controlButton("Select", tone: .active) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isSelecting = true
                    }
                }
                controlButton("Delete All", tone: .danger) {
                    showClearAllConfirm = true
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private enum ControlTone { case neutral, active, danger }

    private func controlButton(_ title: String, tone: ControlTone, action: @escaping () -> Void) -> some View {
        let fg: Color
        let bg: Color
        let stroke: Color
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

    private func detailContextHeader(for record: DiffRecord) -> some View {
        let isAuto = record.source == "Auto"
        let frameID = record.id.uuidString.prefix(4).uppercased()

        return HStack(spacing: 8) {
            Text(isAuto ? "AUTO" : "SCAN")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
            Text("#\(frameID)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(record.timestamp.formatted(.iso8601.year().month().day().dateSeparator(.dash).time(includingFractionalSeconds: false).timeSeparator(.colon)))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer()
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

    private var timelinePane: some View {
        Group {
            if records.isEmpty {
                emptyState
            } else {
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        leftTimelineToolbar
                        ScrollView(.vertical, showsIndicators: true) {
                            LazyVStack(spacing: 0) {
                                ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                                    VStack(spacing: 0) {
                                        if shouldShowDayMarker(for: index, in: records) {
                                            dayMarker(for: record.timestamp)
                                        }

                                        HStack(spacing: 0) {
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
                            .padding(.bottom, 84)
                        }
                        .windowEndFade()
                    }
                    .frame(width: TimelineTheme.leftPaneWidth)

                    Group {
                        if let record = selectedRecord, !record.isEmpty {
                            VStack(spacing: 0) {
                                detailContextHeader(for: record)
                                DashboardDetailPane(
                                    record: record,
                                    storageService: storageService,
                                    horizontalInset: TimelineTheme.rightPaneHorizontalInset,
                                    topInset: TimelineTheme.rightPaneTopInset,
                                    cardCornerRadius: TimelineTheme.rightPaneCardCorner
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

    private var dashboardOverviewPane: some View {
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

                if let record = selectedRecord, record.isEmpty {
                    Text("Selected event has no findings. Summary metrics are shown below.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }

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

    private var sourcesPane: some View {
        HStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(PersistenceLocation.allCases, id: \.rawValue) { location in
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

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 8) {
                        Text(selectedSource.displayName)
                            .font(.system(size: 16, weight: .semibold))
                        Spacer()
                        Text(selectedSourceReferenceText)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                            .lineLimit(2)
                            .frame(maxWidth: 320, alignment: .trailing)
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

                    VStack(alignment: .leading, spacing: 10) {
                        sourceInfoRow("path", value: selectedSource.resolvedPath)
                        sourceInfoRow("watch path", value: selectedSource.watchPath)
                        sourceInfoRow("type", value: selectedSource.isSingleFile ? "single file source" : "directory source")
                        sourceInfoRow("access", value: selectedSource.requiresElevation ? "restricted / elevated" : "readable")
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .rightPaneCardSurface(cornerRadius: TimelineTheme.rightPaneCardCorner)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Text("Current Items")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
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

                    let relatedEvents = records.filter { $0.affectedLocations.contains(selectedSource.rawValue) }

                    if relatedEvents.isEmpty {
                        Text("No timeline events mapped to this source yet.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .rightPaneCardSurface(cornerRadius: TimelineTheme.rightPaneCardCorner)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Recent Events")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)

                            ForEach(Array(relatedEvents.prefix(6)), id: \.id) { record in
                                let isSelected = selectedRecordID == record.id
                                Button {
                                    selectedRecordID = record.id
                                    dashboardTab = .timeline
                                } label: {
                                    HStack(spacing: 8) {
                                        Text(record.timestamp.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits).hour(.twoDigits(amPM: .omitted)).minute()))
                                            .font(.system(size: 12, design: .monospaced))
                                            .foregroundStyle(.secondary)
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

    private var actionsPane: some View {
        let disabled = storageService.activePersistenceActions(of: .disabled)
        let quarantined = storageService.activePersistenceActions(of: .quarantined)

        return HStack(spacing: 12) {
            actionColumnPane(
                title: "Quarantined",
                count: quarantined.count,
                countSubtitle: "ready to restore",
                recordsTitle: "Quarantined Items",
                records: quarantined,
                emptyText: "No quarantined items.",
                actionTitle: "Restore"
            )
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

    private func sourceCard(for location: PersistenceLocation, isSelected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(location.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if location.requiresElevation {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            Text(location.resolvedPath)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .leftPaneCardSurface(selected: isSelected, hovered: false, cornerRadius: 10)
        .opacity(isSelected ? 1.0 : 0.92)
        .saturation(isSelected ? 1.0 : 0.90)
        .orangeHoverShimmer(cornerRadius: 10, opacity: 0.14)
    }

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

    private var currentSourceItems: [PersistenceItem] {
        guard let snapshot = storageService.snapshots.last else { return [] }
        return snapshot.items
            .filter { $0.location == selectedSource }
            .sorted { $0.filename.localizedCaseInsensitiveCompare($1.filename) == .orderedAscending }
    }

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

    @MainActor
    private func restoreActionRecord(_ record: StorageService.PersistenceActionRecord) async {
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

    private var header: some View {
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
    }

    private func breadcrumbTrail(_ trail: [BreadcrumbSegment]) -> some View {
        HStack(spacing: 5) {
            ForEach(Array(trail.enumerated()), id: \.offset) { index, segment in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                Group {
                    if let action = segment.action {
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                action()
                            }
                        } label: {
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
                        .buttonStyle(.plain)
                        .focusable(false)
                    } else {
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

    private var dashboardTabs: some View {
        HStack(spacing: 6) {
            ForEach(DashboardTab.allCases) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        dashboardTab = tab
                    }
                } label: {
                    Text(tab.title)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(dashboardTab == tab ? .primary : .secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            dashboardTab == tab ? Color.accentColor.opacity(0.18) : Color.white.opacity(0.03)
                        )
                    .overlay(
                        Capsule().strokeBorder(
                            dashboardTab == tab ? Color.accentColor.opacity(0.30) : Color.white.opacity(0.10),
                            lineWidth: 0.6
                        )
                    )
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .orangeHoverShimmer(cornerRadius: 999, opacity: 0.11)
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

struct TimelineRowView: View {

    let record: DiffRecord
    let isFirst: Bool
    let isLast: Bool
    let isSelected: Bool
    let isAppeared: Bool
    let onSelect: () -> Void

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
        .opacity(isAppeared ? 1 : 0)
        .offset(y: isAppeared ? 0 : 12)
    }

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

    let record: DiffRecord
    let isSelected: Bool

    @State private var isHovered = false

    private var moodColor: Color {
        if record.isEmpty { return .green }
        if record.removedCount > 0 { return .red }
        if record.addedCount > 0 { return .accentColor }
        return .orange
    }

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
        let restingEmphasis: Double = isSelected ? 1.0 : (isHovered ? 0.95 : 0.88)

        VStack(alignment: .leading, spacing: 0) {
            // Main card content
            VStack(alignment: .leading, spacing: 0) {
                // Top row — cinematic badge + relative time
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

                // Middle row — narrative sentence
                Text(storyText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .padding(.bottom, 8)

                // Bottom row — context spacing
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
        .leftPaneCardSurface(selected: isSelected, hovered: isHovered, cornerRadius: 10)
        .hoverSheen(active: isHovered, opacity: 0.05, cornerRadius: 10)
        .scaleEffect(isHovered ? 1.004 : 1.0)
        .opacity(restingEmphasis)
        .saturation(isSelected ? 1.0 : 0.88)
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
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }

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

    private var detailsIndicatorLabel: String {
        record.isEmpty ? "NO GRAINS" : "VIEW GRAINS"
    }

    private var detailsIndicatorForeground: Color {
        record.isEmpty ? Color.green.opacity(0.86) : Color.orange.opacity(0.92)
    }

    private var detailsIndicatorBackground: Color {
        if record.isEmpty { return Color.green.opacity(0.10) }
        return isSelected ? Color.orange.opacity(0.15) : Color.orange.opacity(0.08)
    }

    private var detailsIndicatorStroke: Color {
        if record.isEmpty { return Color.green.opacity(0.22) }
        return isSelected ? Color.orange.opacity(0.26) : Color.orange.opacity(0.16)
    }

    private var detailsIndicatorWidth: CGFloat {
        record.isEmpty ? 82 : 90
    }

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

struct DashboardDetailPane: View {
    let record: DiffRecord
    let storageService: StorageService
    let horizontalInset: CGFloat
    let topInset: CGFloat
    let cardCornerRadius: CGFloat

    @State private var diff: PersistenceDiff? = nil
    @State private var isLoading = true
    @State private var actionNotice: ActionNotice? = nil
    @State private var actionInFlightPaths: Set<String> = []
    private let helperService = HelperService()

    private struct ActionNotice: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    private enum ItemAction {
        case disable
        case quarantine
    }

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
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.top, 12)
                } else if let diff {
                    eventMetaBlock
                    if !diff.added.isEmpty {
                        detailSection("Added", items: diff.added, tone: .green)
                    }
                    if !diff.removed.isEmpty {
                        detailSection("Removed", items: diff.removed, tone: .red)
                    }
                    if !diff.modified.isEmpty {
                        detailSection("Modified", items: diff.modified.map(\.after), tone: .orange)
                    }
                }
            }
            .padding(.horizontal, horizontalInset)
            .padding(.top, topInset)
            .padding(.bottom, 84)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .windowEndFade()
        .task(id: record.id) { await loadDiff() }
        .alert(item: $actionNotice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var eventMetaBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Event Context")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
                .padding(.bottom, 2)

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

    private var whatText: String {
        let n = record.totalChanges
        return n == 1 ? "1 change detected" : "\(n) changes detected"
    }

    private var scopeText: String {
        if record.resolvedLocations.isEmpty { return "unknown" }
        return record.resolvedLocations.map { $0.shortName.lowercased() }.joined(separator: " · ")
    }

    private func metaRow(_ key: String, value: String) -> some View {
        HStack(spacing: 10) {
            Text(key)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
    }

    private var snapshotText: String {
        guard let pair = storageService.snapshotPair(for: record) else {
            return "pair unavailable"
        }
        let beforeID = pair.before.id.uuidString.prefix(6).uppercased()
        let afterID = pair.after.id.uuidString.prefix(6).uppercased()
        return "#\(beforeID) (\(pair.before.itemCount)) -> #\(afterID) (\(pair.after.itemCount))"
    }

    private func detailSection(_ title: String, items: [PersistenceItem], tone: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(tone.opacity(0.9))

            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(nsImage: responsibleIcon(for: item))
                            .resizable()
                            .frame(width: 16, height: 16)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .padding(.top, 1)
                        Text(item.filename)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if launchActionContext(for: item) != nil {
                            HStack(spacing: 6) {
                                actionTextButton("Quarantine", recommended: true) {
                                    Task { await runItemAction(.quarantine, for: item) }
                                }
                                .help("Move to quarantine folder and stop the service")

                                actionTextButton("Disable", recommended: false) {
                                    Task { await runItemAction(.disable, for: item) }
                                }
                                .help("launchctl disable only")
                            }
                            .disabled(actionInFlightPaths.contains(item.fullPath))
                        }
                        SourceFolderButton(filePath: item.fullPath)
                    }
                    metaInfoRow("source", value: item.location.displayName)
                    metaInfoRow("folder", value: (item.fullPath as NSString).deletingLastPathComponent)
                    if let label = item.label, !label.isEmpty {
                        metaInfoRow("label", value: label)
                    }
                    if let programPath = item.programPath {
                        metaInfoRow("program", value: programPath)
                    }
                    metaInfoRow("file", value: item.fullPath)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .rightPaneCardSurface(cornerRadius: cardCornerRadius)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func responsibleIcon(for item: PersistenceItem) -> NSImage {
        let fm = FileManager.default

        if let bundlePath = item.attribution?.appBundlePath,
           fm.fileExists(atPath: bundlePath) {
            return NSWorkspace.shared.icon(forFile: bundlePath)
        }

        if let programPath = item.programPath {
            if let appBundlePath = appBundlePath(fromProgramPath: programPath),
               fm.fileExists(atPath: appBundlePath) {
                return NSWorkspace.shared.icon(forFile: appBundlePath)
            }
            if fm.fileExists(atPath: programPath) {
                return NSWorkspace.shared.icon(forFile: programPath)
            }
        }

        if fm.fileExists(atPath: item.fullPath) {
            return NSWorkspace.shared.icon(forFile: item.fullPath)
        }

        return NSWorkspace.shared.icon(for: .data)
    }

    private func appBundlePath(fromProgramPath path: String) -> String? {
        var url = URL(fileURLWithPath: path)
        for _ in 0..<12 {
            let currentPath = url.path
            if currentPath == "/" { break }
            if currentPath.hasSuffix(".app") { return currentPath }
            url.deleteLastPathComponent()
        }
        return nil
    }

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

    @MainActor
    private func runItemAction(_ action: ItemAction, for item: PersistenceItem) async {
        guard let ctx = launchActionContext(for: item) else {
            actionNotice = ActionNotice(
                title: "Action unavailable",
                message: "This persistence item type does not support disable/quarantine actions."
            )
            return
        }

        actionInFlightPaths.insert(item.fullPath)
        defer { actionInFlightPaths.remove(item.fullPath) }

        do {
            switch action {
            case .disable:
                try await helperService.disableItem(
                    path: ctx.path,
                    label: ctx.label,
                    domain: ctx.domain,
                    userUID: ctx.userUID
                )
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
            case .quarantine:
                let quarantinedPath = try await helperService.quarantineItem(
                    path: ctx.path,
                    label: ctx.label,
                    domain: ctx.domain,
                    userUID: ctx.userUID,
                    quarantineRoot: ctx.quarantineRoot
                )
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
            }
        } catch {
            actionNotice = ActionNotice(
                title: "Action failed",
                message: error.localizedDescription
            )
        }
    }

    private func metaInfoRow(_ key: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(key)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)
            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func actionTextButton(_ title: String, recommended: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(recommended ? Color.orange : .secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(recommended ? Color.orange.opacity(0.10) : Color.white.opacity(0.03))
                .overlay(
                    Capsule().strokeBorder(
                        recommended ? Color.orange.opacity(0.22) : Color.white.opacity(0.10),
                        lineWidth: 0.6
                    )
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .orangeHoverShimmer(cornerRadius: 999, opacity: 0.11)
    }

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

private struct SourceFolderButton: View {
    let filePath: String
    @State private var isHovered = false

    var body: some View {
        Button {
            revealInFinder(filePath)
        } label: {
            Image(systemName: "folder")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isHovered ? .primary : .secondary)
                .frame(width: 18, height: 18)
                .padding(4)
                .background(isHovered ? Color.white.opacity(0.08) : Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(
                            isHovered ? Color.orange.opacity(0.22) : Color.white.opacity(0.10),
                            lineWidth: 0.6
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .hoverSheen(active: isHovered, opacity: 0.07, cornerRadius: 7)
                .scaleEffect(isHovered ? 1.04 : 1.0)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { isHovered = $0 }
        .help("Reveal source in Finder")
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }

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

private struct HoverSheenModifier: ViewModifier {
    let active: Bool
    let opacity: Double
    let cornerRadius: CGFloat
    @State private var phase: Double = 0

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        AngularGradient(
                        colors: [
                            Color.orange.opacity(0.0),
                            Color.orange.opacity(opacity),
                            Color.orange.opacity(opacity * 0.45),
                            Color.orange.opacity(0.0),
                            Color.orange.opacity(0.0)
                        ],
                        center: .center,
                        angle: .degrees(phase)
                        ),
                        lineWidth: 0.9
                    )
                    .opacity(active ? 1 : 0)
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
            }
            .onAppear {
                updateAnimation(active: active)
            }
            .onChange(of: active) { _, newValue in
                updateAnimation(active: newValue)
            }
    }

    private func updateAnimation(active: Bool) {
        phase = 0
        guard active else { return }
        withAnimation(.linear(duration: 6.0).repeatForever(autoreverses: false)) {
            phase = 360
        }
    }
}

private extension View {
    func hoverSheen(active: Bool, opacity: Double = 0.08, cornerRadius: CGFloat = 10) -> some View {
        modifier(HoverSheenModifier(active: active, opacity: opacity, cornerRadius: cornerRadius))
    }

    func orangeHoverShimmer(cornerRadius: CGFloat = 10, opacity: Double = 0.10) -> some View {
        modifier(OrangeHoverShimmerModifier(cornerRadius: cornerRadius, opacity: opacity))
    }

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

}

private struct OrangeHoverShimmerModifier: ViewModifier {
    let cornerRadius: CGFloat
    let opacity: Double
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .hoverSheen(active: isHovered, opacity: opacity, cornerRadius: cornerRadius)
            .onHover { isHovered = $0 }
    }
}
