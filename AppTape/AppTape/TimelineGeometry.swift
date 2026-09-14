import Foundation

/// The lane's one mapping between points and seconds.
nonisolated struct TimelineGeometry: Equatable {

    /// The divisor's floor.
    static let minimumSpan: Double = 0.001

    /// The lane's floor. A `GeometryReader` reports `0` during the first layout pass, and `px / 0`
    /// is where the `NaN` above comes from.
    static let minimumWidth: Double = 1

    /// How wide the lane is, in points. `>= minimumWidth` and finite, by construction.
    let width: Double

    /// How long the Recording is, in seconds. `>= 0` and finite, by construction.
    let duration: Double

    /// The one place the two floors and the two finiteness guards live.
    init(width: Double, duration: Double) {
        self.width = width.isFinite ? Swift.max(Self.minimumWidth, width) : Self.minimumWidth
        self.duration = duration.isFinite ? Swift.max(0, duration) : 0
    }

    // MARK: - The range

    /// The whole Recording as a range, floored so a divisor taken from it is never zero.
    static func wholeRange(duration: Double) -> ClosedRange<Double> {
        0...Swift.max(duration.isFinite ? duration : 0, minimumSpan)
    }

    /// What the lane shows.
    var visibleRange: ClosedRange<Double> { Self.wholeRange(duration: duration) }

    /// The divisor: the visible range's length, never zero.
    private var span: Double { visibleRange.upperBound }

    /// One column per point, so the waveform always fits the width.
    var columnCount: Int { Int(width) }

    // MARK: - The mapping

    /// Seconds at a point along the lane, clamped to the Recording.
    func time(atX px: Double) -> Double {
        guard px.isFinite else { return 0 }
        return (px / width * span).clamped(to: 0...duration)
    }

    /// The point at a time, deliberately unclamped.
    func x(atTime t: Double) -> Double {
        guard t.isFinite else { return 0 }
        return t / span * width
    }

    /// The distance between two times, in points, never below `minimum`.
    func points(from t0: Double, to t1: Double, minimum: Double) -> Double {
        Swift.max(minimum, x(atTime: t1) - x(atTime: t0))
    }

    // MARK: - Bounded placements

    /// Where to centre a box of `boxWidth` points so it follows `t` without overhanging either end
    /// of the lane.
    func centredBoxX(at t: Double, boxWidth: Double) -> Double {
        let half = Swift.min(Swift.max(0, boxWidth) / 2, width / 2)
        return x(atTime: t).clamped(to: half...(width - half))
    }

    /// Where to place a label that needs `labelWidth` points of room, so the last one cannot run
    /// off the trailing edge.
    func labelX(at t: Double, reserving labelWidth: Double) -> Double {
        let reserve = Swift.min(Swift.max(0, labelWidth), width)
        return x(atTime: t).clamped(to: 0...(width - reserve))
    }

    // MARK: - Hit-testing

    /// How near a handle a press has to land, as a fraction of the lane.
    static let grabToleranceFraction: Double = 0.02

    /// The grab radius in seconds, taken from a fixed fraction of the lane rather than a fixed
    /// number of seconds, so the target is the same physical size whatever the Recording's length.
    var grabTolerance: Double { span * Self.grabToleranceFraction }

    // MARK: - The ruler

    /// The round intervals a ruler is allowed to tick at.
    static let tickCandidates: [Double] = [1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 900, 1800, 3600]

    /// How far apart two tick labels must be before the ladder may stop climbing.
    static let minimumTickSpacing: Double = 64

    /// The first interval on the ladder that keeps two labels at least `minimumTickSpacing` apart.
    /// A function of duration and width alone, because the Recording always fits the width.
    var tickInterval: Double {
        Self.tickCandidates.first { $0 / span * width >= Self.minimumTickSpacing }
            ?? Self.tickCandidates.last!
    }

    /// Every tick time, from zero.
    var ticks: [Double] {
        guard duration > 0 else { return [] }
        return stride(from: 0.0, through: duration, by: tickInterval).map { $0 }
    }
}
