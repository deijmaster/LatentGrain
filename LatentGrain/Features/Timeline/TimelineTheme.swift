import SwiftUI

enum TimelineTheme {
    static let leftPaneWidth: CGFloat = 420
    static let rightPaneMinWidth: CGFloat = 420
    static let rightPaneHorizontalInset: CGFloat = 16
    static let rightPaneTopInset: CGFloat = 14
    static let rightPaneCardCorner: CGFloat = 10
}

extension View {
    func leftPaneCardSurface(selected: Bool, cornerRadius: CGFloat = TimelineTheme.rightPaneCardCorner) -> some View {
        let bg     = selected ? Color.accentColor.opacity(0.16) : Color.white.opacity(0.03)
        let stroke = selected ? Color.accentColor.opacity(0.28) : Color.white.opacity(0.10)

        return background(bg)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(stroke, lineWidth: 0.6)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    func rightPaneCardSurface(selected: Bool = false, cornerRadius: CGFloat = TimelineTheme.rightPaneCardCorner) -> some View {
        background(selected ? Color.accentColor.opacity(0.16) : Color.white.opacity(0.03))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        selected ? Color.accentColor.opacity(0.28) : Color.white.opacity(0.08),
                        lineWidth: 0.6
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
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
