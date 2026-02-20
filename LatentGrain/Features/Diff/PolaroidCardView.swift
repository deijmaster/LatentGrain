import SwiftUI

struct PolaroidCardView: View {

    let title: String
    let snapshot: PersistenceSnapshot?
    let isRevealed: Bool

    private let cardWidth: CGFloat   = 190
    private let photoHeight: CGFloat = 150

    var body: some View {
        VStack(spacing: 0) {
            photoArea
            matteArea
        }
        .frame(width: cardWidth)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 6)
        .shadow(color: .black.opacity(0.10), radius: 2,  x: 0, y: 1)
    }

    // MARK: - Photo area

    @ViewBuilder
    private var photoArea: some View {
        ZStack {
            // Film base — dark when undeveloped, light when revealed
            Rectangle()
                .fill(isRevealed
                      ? Color(red: 0.96, green: 0.94, blue: 0.90)   // warm paper tone
                      : Color(red: 0.08, green: 0.07, blue: 0.09))  // unexposed film
                .frame(height: photoHeight)
                .padding(8)

            if isRevealed, let snapshot {
                revealedContent(snapshot)
                    .transition(.opacity)
            } else {
                undevelopedOverlay
            }
        }
        .frame(height: photoHeight + 16)
        .animation(.easeInOut(duration: 0.6), value: isRevealed)
    }

    private var undevelopedOverlay: some View {
        VStack(spacing: 4) {
            Text("⬛")
                .font(.system(size: 28))
                .opacity(0.15)
            Text("undeveloped")
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.2))
                .kerning(1.5)
                .textCase(.uppercase)
        }
    }

    private func revealedContent(_ snapshot: PersistenceSnapshot) -> some View {
        VStack(spacing: 4) {
            Text("\(snapshot.itemCount)")
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.15, green: 0.15, blue: 0.15))
            Text("items")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color(red: 0.45, green: 0.42, blue: 0.38))
                .textCase(.uppercase)
                .kerning(1.5)

            Rectangle()
                .fill(Color(red: 0.75, green: 0.70, blue: 0.62))
                .frame(width: 80, height: 0.5)
                .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 3) {
                ForEach(
                    snapshot.groupedByLocation
                        .sorted(by: { $0.key.rawValue < $1.key.rawValue }),
                    id: \.key.rawValue
                ) { location, items in
                    HStack {
                        Text(location.displayName)
                            .font(.system(size: 8))
                            .foregroundStyle(Color(red: 0.45, green: 0.42, blue: 0.38))
                            .lineLimit(1)
                        Spacer()
                        Text("\(items.count)")
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color(red: 0.35, green: 0.32, blue: 0.28))
                    }
                    .frame(width: 145)
                }
            }
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Matte area (the white Polaroid border at the bottom)

    private var matteArea: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(Color(red: 0.25, green: 0.25, blue: 0.25))
                .kerning(2.5)
                .textCase(.uppercase)

            if let snapshot {
                Text(snapshot.timestamp, style: .time)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Color(red: 0.55, green: 0.52, blue: 0.48))
            } else {
                Text("—")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Color(red: 0.75, green: 0.72, blue: 0.68))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 14)
    }
}
