import SwiftUI

// MARK: - TimelineView

struct TimelineView: View {

    @EnvironmentObject var storageService: StorageService
    @State private var selectedRecord: DiffRecord? = nil
    @State private var appearedIndices: Set<Int> = []

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
                    ZStack(alignment: .top) {
                        // Central spine — runs full height
                        spineBackground

                        // Node rows — GlassEffectContainer on macOS 26+ for merge/morph
                        let nodeRows = VStack(spacing: 28) {
                            ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                                TimelineNodeView(
                                    record: record,
                                    isLeft: index % 2 == 0,
                                    isAppeared: appearedIndices.contains(index)
                                ) {
                                    selectedRecord = record
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
                        .padding(.vertical, 24)
                        .padding(.horizontal, 12)

                        if #available(macOS 26, *) {
                            GlassEffectContainer(spacing: 28) { nodeRows }
                        } else {
                            nodeRows
                        }
                    }
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
                    Text(record.timestamp.formatted(date: .abbreviated, time: .shortened))
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
        }
        .frame(height: 52)
    }

    // MARK: - Spine background

    private var spineBackground: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(Color.white.opacity(0.15))
                .frame(width: 2)
                .frame(maxHeight: .infinity)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
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

// MARK: - TimelineNodeView

struct TimelineNodeView: View {

    let record: DiffRecord
    let isLeft: Bool
    let isAppeared: Bool
    let onTap: () -> Void

    private var accentColor: Color {
        if record.addedCount > 0 { return .accentColor }
        if record.removedCount > 0 { return .red }
        return .orange
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left card slot (190pt)
            Group {
                if isLeft {
                    TimelineCardView(record: record, accentColor: accentColor, isLeft: true, onTap: onTap)
                } else {
                    Color.clear
                }
            }
            .frame(width: 190)

            // Spine column (40pt) — dot + connector
            ZStack {
                // Horizontal connector line
                if isLeft {
                    HStack(spacing: 0) {
                        Color.white.opacity(0.2)
                            .frame(width: 20, height: 1)
                        Spacer()
                    }
                } else {
                    HStack(spacing: 0) {
                        Spacer()
                        Color.white.opacity(0.2)
                            .frame(width: 20, height: 1)
                    }
                }

                // Spine dot
                Circle()
                    .fill(accentColor)
                    .frame(width: 10, height: 10)
            }
            .frame(width: 40)

            // Right card slot (190pt)
            Group {
                if !isLeft {
                    TimelineCardView(record: record, accentColor: accentColor, isLeft: false, onTap: onTap)
                } else {
                    Color.clear
                }
            }
            .frame(width: 190)
        }
        .opacity(isAppeared ? 1 : 0)
        .offset(x: isAppeared ? 0 : (isLeft ? -16 : 16))
    }
}

// MARK: - TimelineCardView

struct TimelineCardView: View {

    let record: DiffRecord
    let accentColor: Color
    let isLeft: Bool
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .leading) {
                // Full-frame hit area — Spacer and overlay don't register taps
                Color.clear
                // Inner accent bar — on the spine-facing edge
                if isLeft {
                    HStack(spacing: 0) { Spacer(); accentBar }
                } else {
                    HStack(spacing: 0) { accentBar; Spacer() }
                }
                content
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .frame(width: 175, height: 72)
        .modifier(TimelineCardBackgroundModifier(accentColor: accentColor, isHovered: isHovered))
        .padding(isLeft ? .trailing : .leading, 8)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }

    private var accentBar: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(accentColor)
            .frame(width: 3)
            .padding(.vertical, 8)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                sourceBadge
                Text(record.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            HStack(spacing: 4) {
                if record.addedCount > 0 {
                    changePill("+\(record.addedCount)", color: .green)
                }
                if record.removedCount > 0 {
                    changePill("-\(record.removedCount)", color: .red)
                }
                if record.modifiedCount > 0 {
                    changePill("~\(record.modifiedCount)", color: .orange)
                }
            }
        }
        .padding(.leading, isLeft ? 10 : 14)
        .padding(.trailing, isLeft ? 14 : 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sourceBadge: some View {
        let isAuto = record.source == "Auto"
        return Text(isAuto ? "AUTO" : "SCAN")
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
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
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}

// MARK: - TimelineCardBackgroundModifier

/// macOS 26+: Liquid Glass with rounded-rect shape.
/// macOS 13–25: plain opacity background + accent border — the existing dark aesthetic.
struct TimelineCardBackgroundModifier: ViewModifier {
    let accentColor: Color
    let isHovered: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 10))
        } else {
            content
                .background(.white.opacity(isHovered ? 0.08 : 0.05))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(accentColor.opacity(0.2), lineWidth: 0.5)
                )
        }
    }
}

