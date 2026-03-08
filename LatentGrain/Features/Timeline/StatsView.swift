import SwiftUI

// MARK: - StatsView
//
// Full-width infographic dashboard showing aggregate scan analytics.
// Renders inside the "Stats" tab of the persistence timeline.

struct StatsView: View {

    @EnvironmentObject var storageService: StorageService

    private var records: [DiffRecord] { storageService.diffRecords }
    private var snapshots: [PersistenceSnapshot] { storageService.snapshots }

    // MARK: - Aggregate Metrics

    private var totalScans: Int { records.count }
    private var autoScans: Int { records.filter { $0.source == "Auto" }.count }
    private var manualScans: Int { totalScans - autoScans }

    private var totalAdded: Int    { records.reduce(0) { $0 + $1.addedCount } }
    private var totalRemoved: Int  { records.reduce(0) { $0 + $1.removedCount } }
    private var totalModified: Int { records.reduce(0) { $0 + $1.modifiedCount } }
    private var totalChanges: Int  { totalAdded + totalRemoved + totalModified }

    private var avgChangesPerScan: Double {
        guard totalScans > 0 else { return 0 }
        return Double(totalChanges) / Double(totalScans)
    }

    private var disabledCount: Int    { storageService.activePersistenceActions(of: .disabled).count }
    private var quarantinedCount: Int { storageService.activePersistenceActions(of: .quarantined).count }

    // Last 14 days: (day, scan count, change count), oldest → newest
    private var activityData: [(day: String, scans: Int, changes: Int)] {
        let cal = Calendar.current
        let now = Date()
        return (0..<14).map { i -> (day: String, scans: Int, changes: Int) in
            let daysBack = 13 - i
            let date  = cal.date(byAdding: .day, value: -daysBack, to: now)!
            let start = cal.startOfDay(for: date)
            let end   = cal.date(byAdding: .day, value: 1, to: start)!
            let slice = records.filter { $0.timestamp >= start && $0.timestamp < end }
            let label = daysBack == 0
                ? "·"
                : date.formatted(.dateTime.day(.twoDigits))
            return (label, slice.count, slice.reduce(0) { $0 + $1.totalChanges })
        }
    }

    // Events per location summed across all diff records
    private var changesByLocation: [(location: PersistenceLocation, count: Int)] {
        var tally: [PersistenceLocation: Int] = [:]
        for record in records {
            for loc in record.resolvedLocations {
                tally[loc, default: 0] += 1
            }
        }
        return PersistenceLocation.allCases
            .map { ($0, tally[$0, default: 0]) }
            .sorted { $0.count > $1.count }
    }

    // Item counts from the latest snapshot
    private var itemsByLocation: [(location: PersistenceLocation, count: Int)] {
        guard let latest = snapshots.last else { return [] }
        return PersistenceLocation.allCases
            .map { ($0, latest.groupedByLocation[$0]?.count ?? 0) }
            .sorted { $0.count > $1.count }
    }

    // Most-changed location (first with count > 0)
    private var hotLocation: PersistenceLocation? {
        changesByLocation.first(where: { $0.count > 0 })?.location
    }

    // Longest clean streak (consecutive clean records from the most recent)
    private var cleanStreak: Int {
        records.reversed().prefix(while: { $0.totalChanges == 0 }).count
    }

    // Fixed colour palette for each PersistenceLocation (by case order)
    private let locationPalette: [Color] = [
        Color(hue: 0.60, saturation: 0.68, brightness: 0.92),  // blue
        Color(hue: 0.55, saturation: 0.62, brightness: 0.88),  // cyan
        Color(hue: 0.45, saturation: 0.60, brightness: 0.85),  // teal
        Color(hue: 0.35, saturation: 0.58, brightness: 0.80),  // green
        Color(hue: 0.75, saturation: 0.55, brightness: 0.86),  // purple
        Color(hue: 0.80, saturation: 0.58, brightness: 0.83),  // violet
        Color(hue: 0.10, saturation: 0.68, brightness: 0.90),  // amber
        Color(hue: 0.05, saturation: 0.72, brightness: 0.88),  // orange
    ]

    private func color(for location: PersistenceLocation) -> Color {
        let idx = PersistenceLocation.allCases.firstIndex(of: location) ?? 0
        return locationPalette[idx % locationPalette.count]
    }

    // MARK: - Body

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 22) {

                // KPI row
                kpiRow

                // Activity chart
                activitySection

                // Change type + scan source  (two cards, side by side)
                HStack(alignment: .top, spacing: 14) {
                    changeTypeCard.frame(maxWidth: .infinity)
                    scanSourceCard.frame(maxWidth: .infinity)
                }

                // Changes by location + current items side by side
                HStack(alignment: .top, spacing: 14) {
                    changesByLocationCard.frame(maxWidth: .infinity)
                    currentItemsCard.frame(maxWidth: .infinity)
                }

                // Insights row
                insightsRow
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 88)
        }
        .windowEndFade()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - KPI Row

    private var kpiRow: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4),
            spacing: 10
        ) {
            kpiCard(
                label: "Total Scans",
                value: "\(totalScans)",
                note: "\(manualScans) manual · \(autoScans) auto"
            )
            kpiCard(
                label: "Changes Found",
                value: "\(totalChanges)",
                note: String(format: "avg %.1f / scan", avgChangesPerScan)
            )
            kpiCard(
                label: "Items Monitored",
                value: "\(snapshots.last?.itemCount ?? 0)",
                note: "latest snapshot"
            )
            kpiCard(
                label: "Actions Taken",
                value: "\(disabledCount + quarantinedCount)",
                note: "\(disabledCount) disabled · \(quarantinedCount) quarantined"
            )
        }
    }

    private func kpiCard(label: String, value: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
                .tracking(0.8)
            Text(value)
                .font(.system(size: 30, weight: .bold, design: .monospaced))
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.55)
                .lineLimit(1)
            Text(note)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .bottomLeading)
        .padding(12)
        .rightPaneCardSurface(cornerRadius: 10)
    }

    // MARK: - Activity Chart (14 days)

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Scan Activity — Last 14 Days")

            let maxScans   = max(1, activityData.map(\.scans).max()   ?? 1)
            let maxChanges = max(1, activityData.map(\.changes).max() ?? 1)

            GeometryReader { geo in
                let barW   = (geo.size.width - CGFloat(activityData.count - 1) * 3) / CGFloat(activityData.count)
                let chartH = geo.size.height - 18

                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(activityData, id: \.day) { entry in
                        VStack(spacing: 3) {
                            ZStack(alignment: .bottom) {
                                // Baseline track
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.white.opacity(0.05))
                                    .frame(height: chartH)

                                // Scan height bar
                                let scanH = entry.scans == 0
                                    ? 0
                                    : max(4, chartH * CGFloat(entry.scans) / CGFloat(maxScans))

                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.accentColor.opacity(0.35))
                                    .frame(height: scanH)

                                // Changes overlay (proportional slice of the scan bar)
                                if entry.changes > 0 {
                                    let changeH = max(4, scanH * CGFloat(entry.changes) / CGFloat(maxChanges))
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.orange.opacity(0.72))
                                        .frame(height: changeH)
                                }
                            }
                            // Day label
                            Text(entry.day)
                                .font(.system(size: 8, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: barW)
                        }
                        .frame(width: barW)
                    }
                }
            }
            .frame(height: 96)
            .padding(12)
            .rightPaneCardSurface(cornerRadius: 10)

            // Legend
            HStack(spacing: 16) {
                legendItem(Color.accentColor.opacity(0.55), "Scan runs")
                legendItem(Color.orange.opacity(0.72),     "Changes found")
            }
            .padding(.leading, 2)
        }
    }

    // MARK: - Change Type Card

    private var changeTypeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Change Breakdown")

            let total   = max(1, totalAdded + totalRemoved + totalModified)
            let addFrac = CGFloat(totalAdded)    / CGFloat(total)
            let remFrac = CGFloat(totalRemoved)  / CGFloat(total)
            let modFrac = CGFloat(totalModified) / CGFloat(total)

            VStack(alignment: .leading, spacing: 12) {
                // Stacked bar
                GeometryReader { geo in
                    HStack(spacing: 1) {
                        if totalAdded > 0 {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.green.opacity(0.72))
                                .frame(width: max(4, geo.size.width * addFrac))
                        }
                        if totalRemoved > 0 {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.red.opacity(0.72))
                                .frame(width: max(4, geo.size.width * remFrac))
                        }
                        if totalModified > 0 {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.orange.opacity(0.72))
                                .frame(width: max(4, geo.size.width * modFrac))
                        }
                        if totalChanges == 0 {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.white.opacity(0.07))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                .frame(height: 10)

                VStack(spacing: 6) {
                    changeRow("Added",    count: totalAdded,    total: total, color: .green)
                    changeRow("Removed",  count: totalRemoved,  total: total, color: .red)
                    changeRow("Modified", count: totalModified, total: total, color: .orange)
                }
            }
            .padding(12)
            .rightPaneCardSurface(cornerRadius: 10)
        }
    }

    private func changeRow(_ label: String, count: Int, total: Int, color: Color) -> some View {
        let pct = total > 0 ? Int((Double(count) / Double(total)) * 100) : 0
        return HStack(spacing: 6) {
            Circle()
                .fill(color.opacity(0.80))
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(count)")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
            Text("(\(pct)%)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
    }

    // MARK: - Scan Source Card

    private var scanSourceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Scan Origin")

            let total      = max(1, totalScans)
            let autoFrac   = CGFloat(autoScans)   / CGFloat(total)
            let manFrac    = CGFloat(manualScans)  / CGFloat(total)

            VStack(alignment: .leading, spacing: 12) {
                GeometryReader { geo in
                    HStack(spacing: 1) {
                        if autoScans > 0 {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.purple.opacity(0.68))
                                .frame(width: max(4, geo.size.width * autoFrac))
                        }
                        if manualScans > 0 {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.accentColor.opacity(0.68))
                                .frame(width: max(4, geo.size.width * manFrac))
                        }
                        if totalScans == 0 {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.white.opacity(0.07))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                .frame(height: 10)

                VStack(spacing: 6) {
                    changeRow("Auto",   count: autoScans,   total: total, color: .purple)
                    changeRow("Manual", count: manualScans, total: total, color: .accentColor)
                }
            }
            .padding(12)
            .rightPaneCardSurface(cornerRadius: 10)
        }
    }

    // MARK: - Changes by Location

    private var changesByLocationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Events by Location")

            let maxVal = max(1, changesByLocation.map(\.count).max() ?? 1)

            VStack(spacing: 8) {
                ForEach(changesByLocation, id: \.location.rawValue) { entry in
                    GeometryReader { geo in
                        HStack(spacing: 10) {
                            Text(entry.location.shortName)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 96, alignment: .trailing)

                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.white.opacity(0.04))
                                let frac = entry.count == 0
                                    ? 0
                                    : CGFloat(entry.count) / CGFloat(maxVal)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(color(for: entry.location).opacity(0.65))
                                    .frame(width: max(0, (geo.size.width - 96 - 10 - 36 - 10) * frac))
                            }
                            .frame(height: 10)

                            Text("\(entry.count)")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(entry.count > 0 ? .primary : .secondary)
                                .frame(width: 36, alignment: .trailing)
                        }
                    }
                    .frame(height: 13)
                }
            }
            .padding(12)
            .rightPaneCardSurface(cornerRadius: 10)
        }
    }

    // MARK: - Current Items by Location

    private var currentItemsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Current Items by Location")

            let maxVal = max(1, itemsByLocation.map(\.count).max() ?? 1)
            let total  = itemsByLocation.reduce(0) { $0 + $1.count }

            VStack(spacing: 8) {
                ForEach(itemsByLocation, id: \.location.rawValue) { entry in
                    GeometryReader { geo in
                        HStack(spacing: 10) {
                            Text(entry.location.shortName)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 96, alignment: .trailing)

                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.white.opacity(0.04))
                                let frac = entry.count == 0
                                    ? 0
                                    : CGFloat(entry.count) / CGFloat(maxVal)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(color(for: entry.location).opacity(0.48))
                                    .frame(width: max(0, (geo.size.width - 96 - 10 - 36 - 10) * frac))
                            }
                            .frame(height: 10)

                            Text("\(entry.count)")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(entry.count > 0 ? .primary : .secondary)
                                .frame(width: 36, alignment: .trailing)
                        }
                    }
                    .frame(height: 13)
                }
            }
            .padding(12)
            .rightPaneCardSurface(cornerRadius: 10)

            if let latest = snapshots.last {
                Text("Snapshot captured \(latest.timestamp.formatted(.dateTime.year().month(.abbreviated).day().hour().minute())). Total: \(total) items.")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 2)
            }
        }
    }

    // MARK: - Insights Row

    private var insightsRow: some View {
        HStack(spacing: 10) {
            insightCard(
                title: "Scan Frequency",
                body: {
                    guard totalScans > 1,
                          let first = records.min(by: { $0.timestamp < $1.timestamp }),
                          let last  = records.max(by: { $0.timestamp < $1.timestamp }) else {
                        return "Not enough data yet."
                    }
                    let span = last.timestamp.timeIntervalSince(first.timestamp)
                    let days = span / 86_400
                    guard days > 0 else { return "All scans on the same day." }
                    let rate = Double(totalScans) / days
                    return String(format: "%.1f scans/day over %.0f days.", rate, days)
                }()
            )

            insightCard(
                title: "Clean Streak",
                body: cleanStreak > 0
                    ? "\(cleanStreak) consecutive scan\(cleanStreak == 1 ? "" : "s") with no findings."
                    : "Latest scan found changes."
            )

            insightCard(
                title: "Hotspot",
                body: hotLocation.map { "\($0.displayName) has the most events." }
                    ?? "No changes recorded yet."
            )
        }
    }

    private func insightCard(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
                .tracking(0.8)
            Text(body)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
        .padding(12)
        .rightPaneCardSurface(cornerRadius: 10)
    }

    // MARK: - Shared Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(.secondary)
            .tracking(1.0)
    }

    private func legendItem(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 12, height: 6)
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}
