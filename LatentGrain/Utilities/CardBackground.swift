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

    /// Rotating orange angular-gradient border that appears on hover.
    /// Single source of truth for all card hover feedback in the app.
    func orangeHoverShimmer(cornerRadius: CGFloat = 10, opacity: Double = 0.10) -> some View {
        modifier(OrangeHoverShimmerModifier(cornerRadius: cornerRadius, opacity: opacity))
    }

    /// Lower-level shimmer driven by an external `active` flag.
    /// Use `orangeHoverShimmer` for self-contained hover behaviour.
    func hoverSheen(active: Bool, opacity: Double = 0.08, cornerRadius: CGFloat = 10) -> some View {
        modifier(HoverSheenModifier(active: active, opacity: opacity, cornerRadius: cornerRadius))
    }
}

// MARK: - HoverSheenModifier

struct HoverSheenModifier: ViewModifier {
    let active: Bool
    let opacity: Double
    let cornerRadius: CGFloat
    @State private var phase: Double = 0

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        AngularGradient(
                            colors: [
                                Color.orange.opacity(0.0),
                                Color.orange.opacity(opacity),
                                Color.orange.opacity(opacity * 0.45),
                                Color.orange.opacity(0.0),
                                Color.orange.opacity(0.0)
                            ],
                            center: .center,
                            angle: .degrees(phase)
                        ),
                        lineWidth: 0.9
                    )
                    .opacity(active ? 1 : 0)
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
            }
            .onAppear { updateAnimation(active: active) }
            .onChange(of: active) { _, newValue in updateAnimation(active: newValue) }
    }

    private func updateAnimation(active: Bool) {
        phase = 0
        guard active else { return }
        withAnimation(.linear(duration: 6.0).repeatForever(autoreverses: false)) {
            phase = 360
        }
    }
}

// MARK: - OrangeHoverShimmerModifier

struct OrangeHoverShimmerModifier: ViewModifier {
    let cornerRadius: CGFloat
    let opacity: Double
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .hoverSheen(active: isHovered, opacity: opacity, cornerRadius: cornerRadius)
            .onHover { isHovered = $0 }
    }
}
