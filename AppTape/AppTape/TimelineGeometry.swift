//
//  TimelineGeometry.swift
//  AppTape
//

import Foundation

/// The lane's one mapping between points and seconds.
///
/// The Recording always fits the width — one point is `duration ÷ width` (ADR-0023: *"the Recording
/// always fits the width and there is no zoom, so the interval is a function of duration and width
/// alone"*). That sentence used to be a comment, and the code under it carried a `visible` range
/// whose lower bound was provably `0` at all seven sites that subtracted it. This type is that
/// sentence made structural: two scalars in, every derived quantity out.
///
/// **The shape is `Trim`'s, one level up.** `Trim` owns clamping in the time domain and says why:
/// *"The fix is not a better pair of clamps: it is to clamp **once**, into an interval that is
/// provably non-empty, and to have exactly one place that knows how."* The lane had the same
/// problem one domain over — the conversion itself was written five times, the divisor four, and
/// every clamp was a hand-written nested `min`/`max` rather than the `Double.clamped(to:)` `Trim`
/// already publishes. One of those clamps was inverted; see `centredBoxX(at:boxWidth:)`.
///
/// `Trim` also names the hazard this type now absorbs: *"`NaN` is reachable: the lane converts a
/// pixel to a time with `px / width * span`, and a zero-width lane during a layout pass makes that
/// `inf * 0`."* That was defended by a `max(geo.size.width, 1)` floor written at each
/// `GeometryReader`, and by `Trim`'s own `isFinite` guard three files away. It is an invariant of
/// this initialiser now, so no call site carries it.
///
/// Explicitly `nonisolated`, like `Trim` (ADR-0022): nothing here touches UI or disk, and an
/// unannotated type in this target is main-actor isolated. The annotation is load-bearing.
nonisolated struct TimelineGeometry: Equatable {

    /// The divisor's floor. A Recording with no audio yet still has to produce a finite mapping
    /// during the layout pass that draws its empty lane, and `0.001` is small enough that no real
    /// duration is perturbed by it.
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

    /// The whole Recording as a range, floored so a divisor taken from it is never zero. Static
    /// because the sidebar's silhouette needs the same range without a lane to measure
    /// (`EditorView.silhouette`), and it used to spell this out for itself.
    static func wholeRange(duration: Double) -> ClosedRange<Double> {
        0...Swift.max(duration.isFinite ? duration : 0, minimumSpan)
    }

    /// What the lane shows. There is no zoom (ADR-0023), so it is always the whole Recording — the
    /// name is `visible` rather than `whole` only because that is what a zoomable timeline would
    /// call it, and if zoom is ever wanted this is the one member that changes.
    var visibleRange: ClosedRange<Double> { Self.wholeRange(duration: duration) }

    /// The divisor: the visible range's length, never zero.
    private var span: Double { visibleRange.upperBound }

    /// One column per point, so the waveform always fits the width.
    var columnCount: Int { Int(width) }

    // MARK: - The mapping

    /// Seconds at a point along the lane, **clamped to the Recording**.
    ///
    /// It clamps because its result leaves the view: it reaches `Trim.setStart`/`setEnd` and
    /// `AudioPlayer.seek`, and a drag that runs past the lane's edge must land on the Recording's
    /// end rather than past it. A non-finite point reads `0` rather than propagating — `min`/`max`
    /// pass `NaN` through silently, which is how one bad layout pass could have written `nan` into
    /// a Trim xattr.
    func time(atX px: Double) -> Double {
        guard px.isFinite else { return 0 }
        return (px / width * span).clamped(to: 0...duration)
    }

    /// The point at a time, **deliberately unclamped**.
    ///
    /// The asymmetry with `time(atX:)` is correct and has never been written down before. This one
    /// must be free to leave `0...width`: a Trim handle at the very end draws at exactly `width`,
    /// a Dropout band's width is the difference of two of these, and clamping either would collapse a
    /// band that runs off an edge instead of clipping it. Callers that need a bounded result ask
    /// for one by name — `centredBoxX(at:boxWidth:)`, `labelX(at:reserving:)`.
    func x(atTime t: Double) -> Double {
        guard t.isFinite else { return 0 }
        return t / span * width
    }

    /// The distance between two times, in points, never below `minimum`.
    ///
    /// The floor is the caller's: a Dropout that is sub-pixel on an always-fits-the-width lane still
    /// has to be visible (ADR-0010), while the same Dropout inside the loupe is drawn at true width
    /// because the loupe exists to show raw detail.
    func points(from t0: Double, to t1: Double, minimum: Double) -> Double {
        Swift.max(minimum, x(atTime: t1) - x(atTime: t0))
    }

    // MARK: - Bounded placements

    /// Where to centre a box of `boxWidth` points so it follows `t` without overhanging either end
    /// of the lane.
    ///
    /// **The interval is non-empty by construction, and that is the whole point.** This was
    /// `min(max(boxWidth / 2, position), width - boxWidth / 2)` — a lower bound applied first and
    /// an upper bound applied last, over an interval that is empty whenever the lane is narrower
    /// than the box. Below `boxWidth` the upper bound won unconditionally, so the loupe stopped
    /// tracking the drag entirely and sat at a fixed `width - boxWidth / 2`; below `boxWidth / 2`
    /// that number is **negative**, and a 100 pt lane put the loupe 119 pt off its own leading
    /// edge — the one thing the clamp existed to prevent. The inner `max` was dead code at every
    /// width where it mattered.
    ///
    /// On a lane too narrow to avoid both edges there is no correct answer, so the box centres:
    /// it overhangs symmetrically rather than choosing an edge to fall off.
    func centredBoxX(at t: Double, boxWidth: Double) -> Double {
        let half = Swift.min(Swift.max(0, boxWidth) / 2, width / 2)
        return x(atTime: t).clamped(to: half...(width - half))
    }

    /// Where to place a label that needs `labelWidth` points of room, so the last one cannot run
    /// off the trailing edge. Unlike the box above, a label is pulled *in* rather than centred —
    /// it is read left-to-right from its own origin.
    func labelX(at t: Double, reserving labelWidth: Double) -> Double {
        let reserve = Swift.min(Swift.max(0, labelWidth), width)
        return x(atTime: t).clamped(to: 0...(width - reserve))
    }

    // MARK: - Hit-testing

    /// How near a handle a press has to land, as a fraction of the lane.
    static let grabToleranceFraction: Double = 0.02

    /// The grab radius in **seconds**, taken from a fixed fraction of the lane rather than a fixed
    /// number of seconds, so the target is the same physical size whatever the Recording's length.
    /// It is the same always-fits-the-width reasoning the tick ladder uses.
    var grabTolerance: Double { span * Self.grabToleranceFraction }

    // MARK: - The ruler

    /// The round intervals a ruler is allowed to tick at (ADR-0023).
    static let tickCandidates: [Double] = [1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 900, 1800, 3600]

    /// How far apart two tick labels must be before the ladder may stop climbing (ADR-0023).
    static let minimumTickSpacing: Double = 64

    /// The first interval on the ladder that keeps two labels at least `minimumTickSpacing` apart.
    /// A function of duration and width alone, because the Recording always fits the width.
    var tickInterval: Double {
        Self.tickCandidates.first { $0 / span * width >= Self.minimumTickSpacing }
            ?? Self.tickCandidates.last!
    }

    /// Every tick time, from zero.
    ///
    /// **No duration means no ticks, not one tick at zero** (ADR-0031). A lone `0:00` under an
    /// empty lane is a ruler insisting there is a timeline here; there isn't one until the file
    /// stops growing. That is arithmetic here; *whether the duration is trustworthy yet* is the
    /// ruler's own judgement and stays there.
    var ticks: [Double] {
        guard duration > 0 else { return [] }
        return stride(from: 0.0, through: duration, by: tickInterval).map { $0 }
    }
}
