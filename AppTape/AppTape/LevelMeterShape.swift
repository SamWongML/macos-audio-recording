import SwiftUI

/// A live level meter drawn as a compact scroll of vertical bars — one per recent meter fill,
/// oldest at the leading edge — mirrored around the centre line.
nonisolated struct LevelMeterShape: Shape {
    /// Meter fills 0...1, oldest first.
    var fills: [Double]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard !fills.isEmpty else { return path }
        let slot = rect.width / CGFloat(fills.count)
        let barWidth = Swift.max(1, slot * 0.6)
        let mid = rect.midY
        let maxHalf = rect.height / 2
        for (i, fill) in fills.enumerated() {
            let half = Swift.max(0.5, CGFloat(min(1, max(0, fill))) * maxHalf)
            let x = rect.minX + slot * CGFloat(i) + (slot - barWidth) / 2
            let bar = CGRect(x: x, y: mid - half, width: barWidth, height: half * 2)
            path.addRoundedRect(in: bar, cornerSize: CGSize(width: barWidth / 2, height: barWidth / 2))
        }
        return path
    }
}
