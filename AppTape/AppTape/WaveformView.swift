import SwiftUI

/// Amplitude is drawn on a mild power curve; linear peaks make ordinary speech invisible next to
/// one loud transient. 0.65 is close to how Logic and Audacity look.
nonisolated private let drawnCurve: Double = 0.65
nonisolated private func drawn(_ amplitude: Double) -> Double {
    pow(min(1, max(0, amplitude)), drawnCurve)
}

/// The waveform itself.
struct WaveformShape: View {
    var columns: [Envelope.Column]
    var peakStyle: AnyShapeStyle
    var bodyStyle: AnyShapeStyle

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, size in
            guard !columns.isEmpty else { return }
            let mid = size.height / 2
            let scale = size.height / 2 * Envelope.drawnHeadroom
            let step = size.width / Double(columns.count)

            context.fill(
                path(
                    columns.map { ($0.min, $0.max) },
                    size: size, mid: mid, scale: scale, step: step),
                with: .style(peakStyle))
            context.fill(
                path(
                    columns.map { (-$0.rms, $0.rms) },
                    size: size, mid: mid, scale: scale, step: step),
                with: .style(bodyStyle))
        }
    }

    /// No minimum thickness: a column with no signal draws nothing.
    private func path(
        _ pairs: [(Float, Float)], size: CGSize, mid: Double, scale: Double, step: Double
    ) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: mid))
        for (i, pair) in pairs.enumerated() {
            let v = drawn(Double(pair.1))
            p.addLine(to: CGPoint(x: (Double(i) + 0.5) * step, y: mid - v * scale))
        }
        for (i, pair) in pairs.enumerated().reversed() {
            let v = drawn(Double(-pair.0))
            p.addLine(to: CGPoint(x: (Double(i) + 0.5) * step, y: mid + v * scale))
        }
        p.closeSubpath()
        return p
    }
}

/// Same picture, drawn as a `Shape` instead of a `Canvas`.
nonisolated struct WaveformPath: Shape {
    var columns: [Envelope.Column]

    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard !columns.isEmpty else { return p }
        let mid = rect.midY
        let scale = rect.height / 2 * Envelope.drawnHeadroom
        let step = rect.width / Double(columns.count)
        p.move(to: CGPoint(x: 0, y: mid))
        for (i, column) in columns.enumerated() {
            let v = drawn(Double(column.max))
            p.addLine(to: CGPoint(x: (Double(i) + 0.5) * step, y: mid - v * scale))
        }
        for (i, column) in columns.enumerated().reversed() {
            let v = drawn(Double(-column.min))
            p.addLine(to: CGPoint(x: (Double(i) + 0.5) * step, y: mid + v * scale))
        }
        p.closeSubpath()
        return p
    }
}
