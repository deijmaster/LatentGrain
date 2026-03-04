import SwiftUI

// MARK: - CardBackgroundModifier

/// Shared card background for Timeline cards and ScanView banners.
/// macOS 26+: Liquid Glass with rounded-rect shape.
/// macOS 13-25: translucent white background + optional accent border.
struct CardBackgroundModifier: ViewModifier {
    var accentColor: Color?
    var isHovered: Bool
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .background(.white.opacity(isHovered ? 0.08 : 0.05))
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(
                            (accentColor ?? .white).opacity(accentColor != nil ? 0.2 : 0.1),
                            lineWidth: 0.5
                        )
                )
        }
    }
}

extension View {
    func cardBackground(
        accent: Color? = nil,
        hovered: Bool = false,
        cornerRadius: CGFloat = 10
    ) -> some View {
        modifier(CardBackgroundModifier(
            accentColor: accent,
            isHovered: hovered,
            cornerRadius: cornerRadius
        ))
    }

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

// MARK: - Timeline Theme

enum TimelineTheme {
    static let leftPaneWidth: CGFloat = 420
    static let rightPaneMinWidth: CGFloat = 420
    static let rightPaneHorizontalInset: CGFloat = 16
    static let rightPaneTopInset: CGFloat = 14
    static let rightPaneCardCorner: CGFloat = 10
}
