//  PROTOTYPE — throwaway. Pieces lifted unchanged from the source-picker prototype
//  (issue #6, variant H), which is the settled baseline this ticket builds the recording
//  state on top of. Nothing here is up for judgement in issue #8.

import SwiftUI

struct AppIcon: View {
    var source: Source
    var size: CGFloat
    var body: some View {
        Group {
            if let icon = source.icon {
                Image(nsImage: icon).resizable()
            } else {
                Image(systemName: "app.dashed").resizable().foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }
}

/// A real amplitude waveform, mirrored around the row's centre line and scrolling
/// right-to-left, drawn behind the row's content.
///
/// Legibility is the whole difficulty: this sits *under* a title and a subtitle, so it is
/// drawn low-opacity and masked to fade out under the text on the leading edge, leaving
/// the trailing two-thirds — where there is no text — carrying the signal.
struct WaveformBackground: View {
    /// Plain data, deliberately. See `LevelMonitor.waveforms` for why this is not a ring.
    var samples: [Float]
    var isSelected: Bool
    /// Width at the trailing edge the waveform must not draw into, so the record
    /// affordance sits in clear space rather than on top of moving pixels.
    var trailingInset: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Canvas(opaque: false) { context, size in
                Diag.hit("canvasDraw")
                guard samples.count > 1 else { return }

                let midY = size.height / 2
                let step = size.width / CGFloat(samples.count - 1)

                // Points along the top edge, then the same points mirrored back along the
                // bottom, so the outline closes into one shape.
                func point(_ index: Int, mirrored: Bool) -> CGPoint {
                    let amplitude = CGFloat(samples[index]) * midY * 0.92
                    return CGPoint(x: CGFloat(index) * step, y: mirrored ? midY + amplitude : midY - amplitude)
                }

                // Quadratic segments through the midpoints, using each sample as the
                // control point. A straight polyline at this density reads as jagged; the
                // curve is what makes it look like a waveform rather than a chart.
                func trace(_ path: inout Path, mirrored: Bool, reversed: Bool) {
                    let indices = reversed ? Array(samples.indices.reversed()) : Array(samples.indices)
                    guard let first = indices.first else { return }
                    path.addLine(to: point(first, mirrored: mirrored))
                    for offset in 1..<indices.count {
                        let previous = point(indices[offset - 1], mirrored: mirrored)
                        let current = point(indices[offset], mirrored: mirrored)
                        let midpoint = CGPoint(x: (previous.x + current.x) / 2,
                                               y: (previous.y + current.y) / 2)
                        path.addQuadCurve(to: midpoint, control: previous)
                    }
                    path.addLine(to: point(indices[indices.count - 1], mirrored: mirrored))
                }

                var path = Path()
                path.move(to: CGPoint(x: 0, y: midY))
                trace(&path, mirrored: false, reversed: false)
                trace(&path, mirrored: true, reversed: true)
                path.closeSubpath()

                context.fill(path, with: .linearGradient(
                    Gradient(colors: [.accentColor.opacity(0.05), .accentColor.opacity(0.55)]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: size.width, y: 0)))
            }
            .opacity(isSelected ? 0.9 : 0.6)
            // Keep the waveform off the icon and the title.
            .mask(LinearGradient(stops: [
                .init(color: .clear, location: 0.0),
                .init(color: .black.opacity(0.35), location: 0.28),
                .init(color: .black, location: 0.55),
                .init(color: .black, location: 1.0),
            ], startPoint: .leading, endPoint: .trailing))
            .padding(.trailing, trailingInset)
    }
}

/// The empty state B was missing. When `All` is off and nothing is playing, say so —
/// do not silently widen the list and leave the header claiming "Playing Audio".
struct NothingPlaying: View {
    var onShowAll: (() -> Void)?
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "speaker.slash")
                .font(.system(size: 22))
                .foregroundStyle(.tertiary)
            Text("No app is playing audio")
                .font(.callout)
                .foregroundStyle(.secondary)
            if let onShowAll {
                Button("Show All Apps", action: onShowAll)
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
    }
}

