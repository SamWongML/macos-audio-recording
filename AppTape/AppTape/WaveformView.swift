//
//  WaveformView.swift
//  AppTape
//

import SwiftUI

/// The waveform itself. Deliberately dumb: it takes columns as a stored value and draws them —
/// never reading out of a buffer the view cannot observe, so the `Canvas` redraws when its
/// inputs change (issue #6).
struct WaveformShape: View {
    var columns: [Envelope.Column]
    var peakStyle: AnyShapeStyle
    var bodyStyle: AnyShapeStyle
    /// Amplitude is drawn on a mild power curve; linear peaks make ordinary speech invisible
    /// next to one loud transient. 0.65 is close to how Logic and Audacity look.
    var curve: Double = 0.65

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, size in
            guard !columns.isEmpty else { return }
            let mid = size.height / 2
            let scale = size.height / 2
            let step = size.width / Double(columns.count)

            context.fill(path(columns.map { ($0.min, $0.max) },
                              size: size, mid: mid, scale: scale, step: step),
                         with: .style(peakStyle))
            context.fill(path(columns.map { (-$0.rms, $0.rms) },
                              size: size, mid: mid, scale: scale, step: step),
                         with: .style(bodyStyle))
        }
    }

    private func path(_ pairs: [(Float, Float)], size: CGSize, mid: Double, scale: Double, step: Double) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: mid))
        for (i, pair) in pairs.enumerated() {
            let v = shape(Double(pair.1))
            p.addLine(to: CGPoint(x: (Double(i) + 0.5) * step, y: mid - max(v * scale, 0.5)))
        }
        for (i, pair) in pairs.enumerated().reversed() {
            let v = shape(Double(-pair.0))
            p.addLine(to: CGPoint(x: (Double(i) + 0.5) * step, y: mid + max(v * scale, 0.5)))
        }
        p.closeSubpath()
        return p
    }

    private func shape(_ v: Double) -> Double { pow(min(1, max(0, v)), curve) }
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
    var curve: Double = 0.65

    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard !columns.isEmpty else { return p }
        let mid = rect.midY, scale = rect.height / 2
        let step = rect.width / Double(columns.count)
        p.move(to: CGPoint(x: 0, y: mid))
        for (i, column) in columns.enumerated() {
            let v = pow(min(1, max(0, Double(column.max))), curve)
            p.addLine(to: CGPoint(x: (Double(i) + 0.5) * step, y: mid - Swift.max(v * scale, 0.5)))
        }
        for (i, column) in columns.enumerated().reversed() {
            let v = pow(min(1, max(0, Double(-column.min))), curve)
            p.addLine(to: CGPoint(x: (Double(i) + 0.5) * step, y: mid + Swift.max(v * scale, 0.5)))
        }
        p.closeSubpath()
        return p
    }
}
