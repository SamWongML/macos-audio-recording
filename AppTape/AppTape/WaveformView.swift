//
//  WaveformView.swift
//  AppTape
//

import SwiftUI

/// Amplitude is drawn on a mild power curve; linear peaks make ordinary speech invisible next to
/// one loud transient. 0.65 is close to how Logic and Audacity look.
///
/// One constant and one function, beside `Envelope.drawnHeadroom` in spirit: the two renderers
/// below draw the same picture by two different routes, and the shaping was spelled out three
/// times between them — once as a `private func` and twice inline — with the reason above written
/// twice. Two pictures of one Recording must not quietly disagree about its shape.
private let drawnCurve: Double = 0.65
private func drawn(_ amplitude: Double) -> Double {
    pow(min(1, max(0, amplitude)), drawnCurve)
}

/// The waveform itself. Deliberately dumb: it takes columns as a stored value and draws them —
/// never reading out of a buffer the view cannot observe, so the `Canvas` redraws when its
/// inputs change (issue #6).
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

            context.fill(path(columns.map { ($0.min, $0.max) },
                              size: size, mid: mid, scale: scale, step: step),
                         with: .style(peakStyle))
            context.fill(path(columns.map { (-$0.rms, $0.rms) },
                              size: size, mid: mid, scale: scale, step: step),
                         with: .style(bodyStyle))
        }
    }

    /// No minimum thickness: a column with no signal draws **nothing**. The old
    /// `max(v * scale, 0.5)` painted a continuous 1 px bar the full width of the lane, so genuine
    /// silence — the gap between two phrases, which is exactly where an edit lands — read as a
    /// low-level signal that is not there (issue #73, finding 36). The lane's own trough is what
    /// says "timeline here"; the waveform's job is to say only what the audio does.
    private func path(_ pairs: [(Float, Float)], size: CGSize, mid: Double, scale: Double, step: Double) -> Path {
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
///
/// It exists because a `Canvas` inside a `List` row draws **nothing** on macOS 27 (issue #7 —
/// verified with the envelope fully loaded, the frame laid out at its requested size, and a
/// debug border proving the space was reserved; the identical view in a non-lazy `HStack` drew
/// fine). A `Shape` goes through the ordinary render path and works. So: `Canvas` for the big
/// lane, `Shape` for anything inside a `List` row.
struct WaveformPath: Shape {
    var columns: [Envelope.Column]

    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard !columns.isEmpty else { return p }
        let mid = rect.midY, scale = rect.height / 2 * Envelope.drawnHeadroom
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
