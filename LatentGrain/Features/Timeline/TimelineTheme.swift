import SwiftUI

enum TimelineTheme {
    static let leftPaneWidth: CGFloat = 420
    static let rightPaneMinWidth: CGFloat = 420
    static let rightPaneHorizontalInset: CGFloat = 16
    static let rightPaneTopInset: CGFloat = 14
    static let rightPaneCardCorner: CGFloat = 10
}

extension View {
    func leftPaneCardSurface(selected: Bool, hovered: Bool, cornerRadius: CGFloat = TimelineTheme.rightPaneCardCorner) -> some View {
        let bg = selected
            ? Color.accentColor.opacity(0.16)
            : Color.white.opacity(hovered ? 0.08 : 0.03)
        let stroke = selected
            ? Color.accentColor.opacity(0.28)
            : Color.white.opacity(0.10)

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
}
