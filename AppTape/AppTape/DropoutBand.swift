//
//  DropoutBand.swift
//  AppTape
//

import SwiftUI

/// Diagonal hatching clipped to a rect. Hatch rather than a colour is deliberate (ADR-0010): red is
/// the transport (ADR-0004), amber is the Runway (ADR-0009), and a third hue would re-buy that
/// accessibility trade for something less urgent. Hatch also reads as *no data here* rather than
/// *warning*, which is exactly what a Dropout means.
struct HatchPattern: Shape {
    var spacing: CGFloat = 5

    nonisolated func path(in rect: CGRect) -> Path {
        var p = Path()
        // 45° lines sweeping left→right; start far enough left that the top edge is covered too.
        var x = rect.minX - rect.height
        while x < rect.maxX {
            p.move(to: CGPoint(x: x, y: rect.maxY))
            p.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += spacing
        }
        return p
    }
}

/// One Dropout drawn as a hatched band: a faint fill so the gap reads as a region, plus hatch strokes
/// over it. Used both in the lane (with a ~3 pt minimum width so a sub-pixel Dropout is still visible)
/// and in the loupe (at true width). Neutral, not tinted — it is absence, not alarm.
struct DropoutBand: View {
    /// Hatch line spacing; the loupe uses a tighter weave at true width.
    var spacing: CGFloat = 5

    var body: some View {
        Rectangle()
            .fill(.secondary.opacity(0.12))
            .overlay {
                HatchPattern(spacing: spacing)
                    .stroke(.secondary.opacity(0.55), lineWidth: 1)
                    .clipShape(Rectangle())
            }
    }
}
