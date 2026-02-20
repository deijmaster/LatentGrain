import SwiftUI

/// A Polaroid-style card — dark/undeveloped until `isRevealed` is true.
struct PolaroidCardView: View {

    let title: String
    let snapshot: PersistenceSnapshot?
    let isRevealed: Bool

    private let cardWidth: CGFloat   = 188
    private let photoHeight: CGFloat = 148

    var body: some View {
        VStack(spacing: 0) {
            photoArea
            matteArea
        }
        .frame(width: cardWidth)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 4)
    }

    // MARK: - Photo area

    @ViewBuilder
    private var photoArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(isRevealed
                      ? Color(nsColor: .controlBackgroundColor)
                      : Color(red: 0.12, green: 0.11, blue: 0.13))
                .frame(height: photoHeight)
                .padding([.horizontal, .top], 8)

            if isRevealed, let snapshot {
                revealedContent(snapshot)
                    .padding(.top, 8)
                    .transition(.opacity)
            } else {
                Text("—")
                    .font(.system(size: 24, weight: .thin, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.15))
            }
        }
        .frame(height: photoHeight + 8)
        .animation(.easeInOut(duration: 0.6), value: isRevealed)
    }

    private func revealedContent(_ snapshot: PersistenceSnapshot) -> some View {
        VStack(spacing: 4) {
            Text("\(snapshot.itemCount)")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            Text("items")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(1)

            Divider()
                .frame(width: 100)
                .padding(.vertical, 3)

            VStack(alignment: .leading, spacing: 3) {
                ForEach(
                    snapshot.groupedByLocation
                        .sorted(by: { $0.key.rawValue < $1.key.rawValue }),
                    id: \.key.rawValue
                ) { location, items in
                    HStack {
                        Text(location.displayName)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Text("\(items.count)")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 140)
                }
            }
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Matte area

    private var matteArea: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.primary)
                .kerning(2)
                .textCase(.uppercase)

            if let snapshot {
                Text(snapshot.timestamp, style: .time)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            } else {
                Text("—")
                    .font(.system(size: 10))
                    .foregroundStyle(.quaternary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}
