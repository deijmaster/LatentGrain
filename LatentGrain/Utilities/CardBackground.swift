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
}
