import Foundation

/// A **Trim**: the two points that select which part of a Recording is Exported (CONTEXT.md).
/// Choosing them never alters the Recording, so a Trim can be widened, narrowed, or reset at
/// any time — it lives only as two numbers, persisted in an extended attribute.
nonisolated struct Trim: Equatable {
    /// An Export has to contain something.
    static let minimumLength = 0.2

    private(set) var start: Double
    private(set) var end: Double
    let duration: Double

    /// A Recording shorter than the minimum cannot be trimmed at all — the whole thing is the
    /// Trim, and neither handle moves. Adopted-file limits own what else such a
    /// file should do.
    var isFixed: Bool { duration < Self.minimumLength }

    /// The full-length Trim over a Recording of `duration` seconds.
    init(duration: Double) {
        self.duration = duration.isFinite ? Swift.max(0, duration) : 0
        self.start = 0
        self.end = self.duration
    }

    /// Sanitising initialiser: takes any two numbers from anywhere — an xattr written by an
    /// older build, a file since replaced by a shorter one (permits it) — and lands on
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

    /// Reset Trim restores the full range (/ no undo stack — the range *is*
    /// the state, and widening it back is the undo).
    mutating func reset() {
        start = 0
        end = duration
    }
}

nonisolated extension Double {
    func clamped(to limits: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, limits.lowerBound), limits.upperBound)
    }
}
