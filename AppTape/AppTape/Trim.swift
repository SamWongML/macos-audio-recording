//
//  Trim.swift
//  AppTape
//

import Foundation

/// A **Trim**: the two points that select which part of a Recording is Exported (CONTEXT.md).
/// Choosing them never alters the Recording, so a Trim can be widened, narrowed, or reset at
/// any time — it lives only as two numbers, persisted in an extended attribute (ADR-0006).
///
/// **Invalid states are unrepresentable.** Every mutation goes through this type, so no call
/// site ever clamps, and the three invariants below hold by construction:
///
/// - `0 <= start`
/// - `end <= duration`
/// - `end - start >= minimumLength` (unless the Recording is itself shorter than that, in
///   which case the Trim is the whole thing and neither point can move — `isFixed`)
///
/// This shape exists because the ad-hoc version — clamping written out by hand at five
/// separate call sites (drag, keyboard nudge, Mark In, Mark Out, and the xattr reader), each a
/// pair of nested `min`/`max` — held *none* of them: two constraints applied in sequence, and
/// whichever ran second won, so either could push the value straight through the other.
/// Fuzzing that logic found four distinct failures — past the end, before the beginning,
/// crossed handles, and a Recording shorter than the minimum making the rule unsatisfiable —
/// plus a `NaN` that propagated silently through `min`/`max` and would have been written into
/// the xattr, breaking the Recording permanently on the next open. The fix is not a better
/// pair of clamps: it is to clamp **once**, into an interval that is provably non-empty, and to
/// have exactly one place that knows how. (Settled in issue #7's prototype; see its README.)
struct Trim: Equatable {
    /// An Export has to contain something.
    static let minimumLength = 0.2

    private(set) var start: Double
    private(set) var end: Double
    let duration: Double

    /// A Recording shorter than the minimum cannot be trimmed at all — the whole thing is the
    /// Trim, and neither handle moves. Adopted-file limits (issue #30) own what else such a
    /// file should do.
    var isFixed: Bool { duration < Self.minimumLength }

    /// The full-length Trim over a Recording of `duration` seconds.
    init(duration: Double) {
        self.duration = duration.isFinite ? Swift.max(0, duration) : 0
        self.start = 0
        self.end = self.duration
    }

    /// Sanitising initialiser: takes any two numbers from anywhere — an xattr written by an
    /// older build, a file since replaced by a shorter one (ADR-0006 permits it) — and lands on
    /// a valid Trim rather than trusting them or trapping.
    init(start: Double, end: Double, duration: Double) {
        self = Trim(duration: duration)
        guard !isFixed else { return }
        setEnd(end)
        setStart(start)
    }

    var range: ClosedRange<Double> { start...end }
    var lowerBound: Double { start }
    var upperBound: Double { end }
    var length: Double { end - start }

    /// Within half a millisecond of the full length, so a Trim reset to the whole Recording —
    /// or one that never moved — reads as untrimmed and skips the scissors chrome and the xattr.
    var isWholeRecording: Bool { start <= 0.0005 && end >= duration - 0.0005 }

    /// The interval `start` is allowed to occupy. Non-empty whenever the Recording is longer
    /// than the minimum, because `end` is itself never below `minimumLength`.
    private var startLimits: ClosedRange<Double> { 0...Swift.max(0, end - Self.minimumLength) }
    private var endLimits: ClosedRange<Double> {
        Swift.min(duration, start + Self.minimumLength)...duration
    }

    /// Non-finite input leaves the Trim alone rather than moving a handle to nowhere. `NaN` is
    /// reachable: the lane converts a pixel to a time with `px / width * span`, and a zero-width
    /// lane during a layout pass makes that `inf * 0`. `min` and `max` propagate `NaN` silently,
    /// so without this guard one bad layout would write `nan` into the xattr and the Recording
    /// would come back broken on the next launch.
    mutating func setStart(_ t: Double) {
        guard !isFixed, t.isFinite else { return }
        start = t.clamped(to: startLimits)
    }

    mutating func setEnd(_ t: Double) {
        guard !isFixed, t.isFinite else { return }
        end = t.clamped(to: endLimits)
    }

    mutating func nudgeStart(by delta: Double) { setStart(start + delta) }
    mutating func nudgeEnd(by delta: Double) { setEnd(end + delta) }

    /// Reset Trim restores the full range (ADR-0006 / issue #7: no undo stack — the range *is*
    /// the state, and widening it back is the undo).
    mutating func reset() {
        start = 0
        end = duration
    }
}

extension Double {
    func clamped(to limits: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, limits.lowerBound), limits.upperBound)
    }
}
