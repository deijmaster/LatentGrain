import SwiftUI

// MARK: - PolaroidCardView
//
// Visual structure (all measurements in pt):
//
//   ┌──────────────────┐  ─┐
//   │ ░░░░░░░░░░░░░░░░ │   │ 4pt top border (white)
//   │ ░┌────────────┐░ │   │
//   │ ░│            │░ │   │ film area: 46 × 40 dark rectangle
//   │ ░│  (dark)    │░ │   │ 4pt side borders (white)
//   │ ░│            │░ │   │
//   │ ░└────────────┘░ │   │
//   │                  │   │ 16pt bottom matte (white) — the classic
//   └──────────────────┘  ─┘   Polaroid proportion: ~4× the side border
//
// Total card size: 54 × 60 pt
// Slight −3° rotation applied at the call site (DiffView.polaroid)

struct PolaroidCardView: View {

    var body: some View {
        Rectangle()
            // Near-black with a very slight warm tint — matches unexposed film
            .fill(Color(red: 0.08, green: 0.07, blue: 0.09))
            .frame(width: 46, height: 40)
            // Thin border on top and sides; thick matte at the bottom
            .padding(.top, 4)
            .padding(.horizontal, 4)
            .padding(.bottom, 16)
            // White Polaroid body
            .background(Color(white: 0.92))
            // Tight corner — physical Polaroid cards have a very small radius
            .clipShape(RoundedRectangle(cornerRadius: 3))
            // Two-layer shadow: soft ambient lift + crisp contact shadow
            .shadow(color: .black.opacity(0.30), radius: 8, x: 0, y: 4)
            .shadow(color: .black.opacity(0.12), radius: 2, x: 0, y: 1)
    }
}

// MARK: - Previews

#Preview("Polaroid", traits: .fixedLayout(width: 160, height: 140)) {
    PolaroidCardView()
        .padding(40)
        .background(Color(white: 0.12))
        .preferredColorScheme(.dark)
}
