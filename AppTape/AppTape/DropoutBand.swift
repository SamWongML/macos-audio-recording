import SwiftUI

/// Diagonal hatching clipped to a rect.
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

/// One Dropout drawn as a hatched band: a faint fill so the gap reads as a region, plus hatch
/// strokes over it.
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
