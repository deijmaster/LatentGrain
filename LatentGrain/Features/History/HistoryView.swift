import SwiftUI

/// Snapshot history — gated behind Pro Mode (StoreKit integration in Phase 4).
struct HistoryView: View {

    var onClose: () -> Void = {}
    @EnvironmentObject var storageService: StorageService
    @AppStorage("proMode") private var proMode = false
    @State private var selectedRecord: DiffRecord? = nil
    @State private var searchText = ""

    /// All searchable text strings extracted from a record's after-snapshot items.
    /// Covers filenames, reverse-DNS labels, binary names, and location names —
    /// the same fields searched in DiffView — so history search is full-content.
    private func itemStrings(for record: DiffRecord) -> [String] {
        guard let pair = storageService.snapshotPair(for: record) else { return [] }
        let items = pair.after.items
        var strings: [String] = []
        strings += items.map { $0.filename }
        strings += items.compactMap { $0.label }
        strings += items.compactMap { $0.programPath }
            .map { URL(fileURLWithPath: $0).lastPathComponent }
            .filter { !$0.isEmpty }
        strings += items.map { $0.location.displayName }
        return strings
    }

    private var filteredRecords: [DiffRecord] {
        let all = storageService.diffRecords.reversed() as [DiffRecord]
        guard !searchText.isEmpty else { return all }
        let q = searchText.lowercased()
        return all.filter { record in
            record.source.lowercased().contains(q)
            || record.timestamp.formatted(date: .abbreviated, time: .shortened).lowercased().contains(q)
            || record.timestamp.formatted(.dateTime.month(.abbreviated).year()).lowercased().contains(q)
            || (record.addedCount    > 0 && "added".contains(q))
            || (record.removedCount  > 0 && "removed".contains(q))
            || (record.modifiedCount > 0 && "modified".contains(q))
            || "\(record.totalChanges)".contains(q)
            || "\(record.addedCount) added".contains(q)
            || "\(record.removedCount) removed".contains(q)
            || "\(record.modifiedCount) modified".contains(q)
            || itemStrings(for: record).contains { $0.lowercased().contains(q) }
        }
    }

    /// Suggestion chips — driven by everything searchable in the records,
    /// including the full item content (filenames, labels, binary names) from each snapshot.
    private var suggestions: [String] {
        guard !searchText.isEmpty else { return [] }
        let q = searchText.lowercased()
        var pool: [String] = []

        // Source types
        pool += Set(storageService.diffRecords.map { $0.source }).sorted()

        // Change-type keywords
        pool += ["added", "removed", "modified"]

        // Month + year strings
        pool += Set(storageService.diffRecords.map {
            $0.timestamp.formatted(.dateTime.month(.abbreviated).year())
        }).sorted()

        // Full abbreviated dates
        pool += Set(storageService.diffRecords.map {
            $0.timestamp.formatted(date: .abbreviated, time: .omitted)
        }).sorted()

        // Count-based phrases that exist in real data
        pool += storageService.diffRecords.flatMap { record -> [String] in
            var parts: [String] = []
            if record.addedCount    > 0 { parts.append("\(record.addedCount) added") }
            if record.removedCount  > 0 { parts.append("\(record.removedCount) removed") }
            if record.modifiedCount > 0 { parts.append("\(record.modifiedCount) modified") }
            return parts
        }

        // Full item content from every record's after-snapshot
        for record in storageService.diffRecords {
            pool += itemStrings(for: record)
        }

        return Array(Set(
            pool.filter { !$0.isEmpty && $0.lowercased().contains(q) && $0.lowercased() != q }
        ))
        .sorted()
        .prefix(8)
        .map { $0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if proMode {
                if let record = selectedRecord {
                    DiffDetailView(record: record, storageService: storageService)
                } else if storageService.diffRecords.isEmpty {
                    emptyState
                } else {
                    recordList
                }
            } else {
                premiumGate
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Header

    private var header: some View {
        ZStack {
            HStack {
                // Left: back button when in detail, empty otherwise
                if selectedRecord != nil {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            selectedRecord = nil
                            searchText = ""
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 12, weight: .semibold))
                            Text("History")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                }

                Spacer()

                // Right: always-visible close button
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .background(.white.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help("Close History")
            }
            .padding(.horizontal, 14)

            if let record = selectedRecord {
                // Show the detection's timestamp as the detail title
                VStack(spacing: 1) {
                    Text(record.source == "Auto" ? "Auto Detection" : "Manual Scan")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    Text(record.timestamp.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            } else {
                let count = storageService.diffRecords.count
                VStack(spacing: 1) {
                    Text("Detection History")
                        .font(.system(.headline, design: .monospaced))
                    if count > 0 {
                        Text("\(count) detection\(count == 1 ? "" : "s")")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(height: 52)
    }

    // MARK: - Record list

    private var recordList: some View {
        VStack(spacing: 0) {
            SearchBar(
                text: $searchText,
                placeholder: "Search by date, source, or change type…",
                suggestions: suggestions
            )
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Divider()

            if filteredRecords.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                    Text("No results for \"\(searchText)\"")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredRecords) { record in
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    selectedRecord = record
                                }
                            } label: {
                                DiffRecordRowView(record: record) {
                                    storageService.deleteDiffRecord(id: record.id)
                                }
                            }
                            .buttonStyle(.plain)
                            .focusable(false)
                        }
                    }
                    .padding(12)
                }
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "film")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            VStack(spacing: 4) {
                Text("No detections yet")
                    .font(.system(.body, design: .monospaced).weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("Manual scans and auto-detected changes\nwill appear here.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Premium gate

    private var premiumGate: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.fill")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                Text("History requires Premium")
                    .font(.system(.body, design: .monospaced).weight(.semibold))
                Text("Unlimited detection history, PDF/JSON export,\nand auto-scan — one purchase.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                // TODO (Phase 4): open StoreKit purchase sheet
            } label: {
                NavButton(label: "Upgrade to Premium", direction: .forward)
            }
            .buttonStyle(.plain)
            .focusable(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - DiffRecordRowView

struct DiffRecordRowView: View {

    let record: DiffRecord
    var onDelete: (() -> Void)? = nil

    @State private var isHovered = false

    /// Dominant accent colour — reflects the most significant change type in this detection.
    private var accent: Color {
        let a = record.addedCount, r = record.removedCount, m = record.modifiedCount
        if a >= r && a >= m && a > 0 { return .green }
        if r >= a && r >= m && r > 0 { return .red }
        return .orange
    }

    var body: some View {
        HStack(spacing: 0) {
            // Accent bar — matches ItemRow style from DiffView
            Rectangle()
                .fill(accent)
                .frame(width: 3)
                .clipShape(UnevenRoundedRectangle(
                    topLeadingRadius: 8, bottomLeadingRadius: 8,
                    bottomTrailingRadius: 0, topTrailingRadius: 0
                ))

            // Content — badge, timestamp, pills
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    sourceBadge
                    Text(record.timestamp.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.primary)
                }

                HStack(spacing: 6) {
                    if record.addedCount > 0 {
                        changePill("+\(record.addedCount) added", color: .green)
                    }
                    if record.removedCount > 0 {
                        changePill("-\(record.removedCount) removed", color: .red)
                    }
                    if record.modifiedCount > 0 {
                        changePill("≈\(record.modifiedCount) modified", color: .orange)
                    }
                }
            }
            .padding(.leading, 12)
            .frame(maxWidth: .infinity, minHeight: 56, maxHeight: 56, alignment: .leading)

            // Trailing action — lives in the outer HStack so it centres against the full row height
            if isHovered, let onDelete {
                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.red.opacity(0.85))
                        .frame(width: 28, height: 28)
                        .background(.red.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .focusable(false)
                .transition(.opacity)
                .padding(.trailing, 10)
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 28, height: 28)
                    .padding(.trailing, 10)
            }
        }
        .background(.white.opacity(0.06))
        .background(accent.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(accent.opacity(0.18), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }

    private var sourceBadge: some View {
        let isAuto = record.source == "Auto"
        return Text(isAuto ? "AUTO" : "SCAN")
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(isAuto ? Color.accentColor : .secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(isAuto ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.1))
            .overlay(
                Capsule().strokeBorder(
                    isAuto ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.2),
                    lineWidth: 1
                )
            )
            .clipShape(Capsule())
    }

    private func changePill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.1))
            .clipShape(Capsule())
    }
}

// MARK: - DiffDetailView

/// Reconstructs a full diff from a DiffRecord's snapshot pair and renders it using DiffView.
struct DiffDetailView: View {

    let record: DiffRecord
    let storageService: StorageService

    @State private var diff: PersistenceDiff? = nil

    var body: some View {
        Group {
            if let diff {
                // Always revealed — user is reviewing history, not discovering for the first time
                DiffView(diff: diff, isRevealed: true, showPolaroids: false) {}
                    .frame(maxHeight: .infinity)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("Snapshots no longer available")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("The underlying snapshots may have been pruned.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 260)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { reconstruct() }
    }

    private func reconstruct() {
        guard let pair = storageService.snapshotPair(for: record) else { return }
        diff = DiffService().diff(before: pair.before, after: pair.after)
    }
}
