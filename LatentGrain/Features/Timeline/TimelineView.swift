import SwiftUI

// MARK: - TimelineView

struct TimelineView: View {

    @EnvironmentObject var storageService: StorageService
    @State private var selectedRecord: DiffRecord? = nil
    @State private var expandedID: UUID? = nil
    @State private var appearedIndices: Set<Int> = []
    @State private var showClearAllConfirm = false
    @State private var isSelecting = false
    @State private var selectedIDs: Set<UUID> = []

    private var records: [DiffRecord] {
        storageService.diffRecords.reversed()
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if let record = selectedRecord {
                DiffDetailView(record: record, storageService: storageService)
            } else if records.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                            HStack(spacing: 0) {
                                if isSelecting {
                                    Image(systemName: selectedIDs.contains(record.id) ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 16))
                                        .foregroundStyle(selectedIDs.contains(record.id) ? Color.accentColor : .secondary)
                                        .frame(width: 28)
                                        .padding(.leading, 6)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                                if selectedIDs.contains(record.id) {
                                                    selectedIDs.remove(record.id)
                                                } else {
                                                    selectedIDs.insert(record.id)
                                                }
                                            }
                                        }
                                        .transition(.move(edge: .leading).combined(with: .opacity))
                                }

                                TimelineRowView(
                                    record: record,
                                    isFirst: index == 0,
                                    isLast: index == records.count - 1,
                                    isExpanded: !isSelecting && expandedID == record.id,
                                    isAppeared: appearedIndices.contains(index),
                                    onToggleExpand: {
                                        if isSelecting {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                                if selectedIDs.contains(record.id) {
                                                    selectedIDs.remove(record.id)
                                                } else {
                                                    selectedIDs.insert(record.id)
                                                }
                                            }
                                        } else {
                                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                                expandedID = expandedID == record.id ? nil : record.id
                                            }
                                        }
                                    },
                                    onViewDetail: { selectedRecord = record },
                                    onDelete: {
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                            if expandedID == record.id { expandedID = nil }
                                            storageService.deleteDiffRecord(id: record.id)
                                        }
                                    },
                                    storageService: storageService
                                )
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
                    .padding(.vertical, 12)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Header

    private var header: some View {
        ZStack {
            HStack {
                if selectedRecord != nil {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            selectedRecord = nil
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Timeline")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                }
                Spacer()
            }
            .padding(.horizontal, 14)

            if let record = selectedRecord {
                VStack(spacing: 1) {
                    Text(record.source == "Auto" ? "Auto Detection" : "Manual Scan")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    Text(record.timestamp.formatted(.iso8601.year().month().day().dateSeparator(.dash).time(includingFractionalSeconds: false).timeSeparator(.colon)))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 64)
            } else {
                let count = records.count
                VStack(spacing: 1) {
                    Text("Persistence Timeline")
                        .font(.system(.headline, design: .monospaced))
                    if count > 0 {
                        Text("\(count) event\(count == 1 ? "" : "s")")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack(spacing: 8) {
                Spacer()
                if selectedRecord == nil, !records.isEmpty {
                    if isSelecting {
                        if !selectedIDs.isEmpty {
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    for id in selectedIDs {
                                        storageService.deleteDiffRecord(id: id)
                                    }
                                    selectedIDs.removeAll()
                                    expandedID = nil
                                }
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 12, weight: .medium))
                                    Text("\(selectedIDs.count)")
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                }
                                .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                            .focusable(false)
                            .help("Delete selected events")
                        }

                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                isSelecting = false
                                selectedIDs.removeAll()
                            }
                        } label: {
                            Text("Done")
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                    } else {
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                isSelecting = true
                                expandedID = nil
                            }
                        } label: {
                            Text("Select")
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .focusable(false)

                        Button {
                            showClearAllConfirm = true
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                        .help("Clear all timeline events")
                    }
                }
            }
            .padding(.horizontal, 14)
        }
        .frame(height: 52)
        .alert("Clear Timeline", isPresented: $showClearAllConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Clear All", role: .destructive) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    expandedID = nil
                    storageService.deleteAllDiffRecords()
                }
            }
        } message: {
            Text("This will remove all timeline events. This cannot be undone.")
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
                    .font(.system(.body, design: .monospaced).weight(.semibold))
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
    let isExpanded: Bool
    let isAppeared: Bool
    let onToggleExpand: () -> Void
    let onViewDetail: () -> Void
    let onDelete: () -> Void
    let storageService: StorageService

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
                accentColor: accentColor,
                isExpanded: isExpanded,
                onToggleExpand: onToggleExpand,
                onViewDetail: onViewDetail,
                onDelete: onDelete,
                storageService: storageService
            )
            .contentShape(Rectangle())
            .onTapGesture(perform: onToggleExpand)
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
    let accentColor: Color
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let onViewDetail: () -> Void
    let onDelete: () -> Void
    let storageService: StorageService

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main card content
            HStack(spacing: 0) {
                // Leading accent bar
                RoundedRectangle(cornerRadius: 2)
                    .fill(accentColor)
                    .frame(width: 3)
                    .padding(.vertical, 8)

                VStack(alignment: .leading, spacing: 0) {
                    // Top row — location pills (where), source badge (how), timestamp, chevron
                    HStack(spacing: 5) {
                        ForEach(record.resolvedLocations, id: \.rawValue) { location in
                            locationPill(location)
                        }
                        sourceBadge
                        Spacer()
                        Text(record.timestamp.formatted(.iso8601.year().month().day().dateSeparator(.dash).time(includingFractionalSeconds: false).timeSeparator(.colon)))
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.bottom, 8)

                    // Bottom row — change pills
                    HStack(spacing: 4) {
                        if record.addedCount > 0 {
                            changePill("+\(record.addedCount) added", color: .green)
                        }
                        if record.removedCount > 0 {
                            changePill("-\(record.removedCount) removed", color: .red)
                        }
                        if record.modifiedCount > 0 {
                            changePill("~\(record.modifiedCount) modified", color: .orange)
                        }
                        if record.isEmpty {
                            changePill("no changes", color: .green)
                        }

                        Spacer(minLength: 0)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
            }

            // Inline expansion
            if isExpanded {
                Divider()
                    .padding(.horizontal, 10)
                InlineExpansionView(
                    record: record,
                    storageService: storageService,
                    onViewDetail: onViewDetail,
                    onDelete: onDelete
                )
            }
        }
        .cardBackground(accent: accentColor, hovered: isHovered)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }

    private var sourceBadge: some View {
        let isAuto = record.source == "Auto"
        return Text(isAuto ? "AUTO" : "SCAN")
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .foregroundStyle(isAuto ? Color.accentColor : .secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(isAuto ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.1))
            .overlay(
                Capsule().strokeBorder(
                    isAuto ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.2),
                    lineWidth: 0.5
                )
            )
            .clipShape(Capsule())
    }

    private func changePill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private func locationPill(_ location: PersistenceLocation) -> some View {
        let color = location.badgeColor
        return Text(location.shortName)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.1))
            .overlay(
                Capsule().strokeBorder(color.opacity(0.3), lineWidth: 0.5)
            )
            .clipShape(Capsule())
    }
}

// MARK: - InlineExpansionView

struct InlineExpansionView: View {

    let record: DiffRecord
    let storageService: StorageService
    let onViewDetail: () -> Void
    let onDelete: () -> Void

    @State private var diff: PersistenceDiff? = nil
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                    Spacer()
                }
                .padding(.vertical, 10)
            } else if let diff {
                // Added
                if !diff.added.isEmpty {
                    itemSection("Added", items: diff.added, color: .green)
                }

                // Removed
                if !diff.removed.isEmpty {
                    itemSection("Removed", items: diff.removed, color: .red)
                }

                // Modified
                if !diff.modified.isEmpty {
                    let modItems = diff.modified.map(\.after)
                    itemSection("Modified", items: modItems, color: .orange)
                }

                // Actions row
                HStack {
                    Button(action: onViewDetail) {
                        HStack(spacing: 4) {
                            Text("View Full Detail")
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)

                    Spacer()

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .help("Delete this event")
                }
                .padding(.vertical, 6)
            } else {
                HStack {
                    Text("Snapshots no longer available")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .help("Delete this event")
                }
                .padding(.vertical, 8)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .task(id: record.id) {
            await loadDiff()
        }
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

        // Backfill affectedLocations for old records that predate this field
        if record.affectedLocations.isEmpty, !result.affectedLocationValues.isEmpty {
            var updated = record
            updated.affectedLocations = result.affectedLocationValues
            storageService.updateDiffRecord(updated)
        }
    }

    private func itemSection(_ title: String, items: [PersistenceItem], color: Color) -> some View {
        let capped = Array(items.prefix(5))
        let overflow = items.count - capped.count

        return VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)

            ForEach(capped) { item in
                HStack(spacing: 5) {
                    Circle()
                        .fill(color)
                        .frame(width: 5, height: 5)
                    Text(item.filename)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer()
                }
            }

            if overflow > 0 {
                Text("+ \(overflow) more")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 10)
            }
        }
    }
}
