import Testing
import Foundation
@testable import AppTape

/// The lane's one mapping between points and seconds.
struct TimelineGeometryTests {
    /// The lane at the editor's default window size, over a 90 s Recording.
    private let lane = TimelineGeometry(width: 760, duration: 90)

    // MARK: - The invariants the initialiser establishes

    /// Every floor and finiteness guard that used to be written at the call sites — two
    /// `max(geo.size.width, 1)`s, a `max(duration, 0.001)`, and `Trim`'s `isFinite` three files
    /// away — now holds by construction.
    @Test func theInitialiserFloorsEveryHostileInput() {
        for bad: Double in [0, -1, -1e18, .nan, .infinity, -.infinity] {
            let g = TimelineGeometry(width: bad, duration: 90)
            #expect(g.width == TimelineGeometry.minimumWidth, "width \(bad) escaped the floor")
        }
        for bad: Double in [-1, -1e18, .nan, .infinity, -.infinity] {
            let g = TimelineGeometry(width: 760, duration: bad)
            #expect(g.duration == 0, "duration \(bad) escaped the floor")
        }
        #expect(TimelineGeometry(width: 760, duration: .infinity).duration == 0)
        #expect(TimelineGeometry(width: .infinity, duration: 90).width == 1)
    }

    /// A Recording with no audio yet still lays out: the divisor is floored, so nothing divides by
    /// zero during the pass that draws its empty lane.
    @Test func aZeroLengthRecordingStillProducesAFiniteMapping() {
        let empty = TimelineGeometry(width: 760, duration: 0)
        #expect(empty.x(atTime: 0).isFinite)
        #expect(empty.time(atX: 380).isFinite)
        #expect(empty.time(atX: 380) == 0)          // clamped to a zero-length Recording
        #expect(empty.visibleRange.upperBound == TimelineGeometry.minimumSpan)
    }

    /// The range the sidebar's row waveform used to spell out for itself.
    @Test func theWholeRangeIsTheSameFromEitherDoor() {
        #expect(lane.visibleRange == TimelineGeometry.wholeRange(duration: 90))
        #expect(TimelineGeometry.wholeRange(duration: 0).upperBound == TimelineGeometry.minimumSpan)
        #expect(TimelineGeometry.wholeRange(duration: -5).upperBound == TimelineGeometry.minimumSpan)
        #expect(TimelineGeometry.wholeRange(duration: .nan).upperBound == TimelineGeometry.minimumSpan)
        #expect(TimelineGeometry.wholeRange(duration: 90) == 0...90)
    }

    // MARK: - The mapping, both ways

    @Test func theEndsOfTheLaneAreTheEndsOfTheRecording() {
        #expect(lane.time(atX: 0) == 0)
        #expect(abs(lane.time(atX: 760) - 90) < 1e-9)
        #expect(lane.x(atTime: 0) == 0)
        #expect(abs(lane.x(atTime: 90) - 760) < 1e-9)
        #expect(abs(lane.x(atTime: 45) - 380) < 1e-9)
    }

    /// `time(atX:)` clamps because its result leaves the view — it reaches `Trim` and `AudioPlayer`.
    @Test func timeIsClampedToTheRecording() {
        #expect(lane.time(atX: -500) == 0)
        #expect(lane.time(atX: 10_000) == 90)
        #expect(lane.time(atX: .nan) == 0)
        #expect(lane.time(atX: .infinity) == 0)
    }

    /// `x(atTime:)` is not clamped, and that asymmetry is the decision: a handle at the very end
    /// draws at exactly `width`, and a Dropout band's width is the difference of two of these.
    @Test func xIsDeliberatelyUnclamped() {
        #expect(lane.x(atTime: 180) > lane.width)
        #expect(lane.x(atTime: -10) < 0)
        #expect(lane.x(atTime: .nan) == 0)          // non-finite still refuses to propagate
    }

    /// Round-tripping a point through both directions returns it. This is the property the two
    /// hand-written copies could disagree about and nothing would have caught it.
    @Test func aPointSurvivesTheRoundTrip() {
        for width in [1.0, 37.0, 212.0, 760.0, 4096.0] {
            for duration in [0.2, 1.0, 30.0, 90.0, 5400.0] {
                let g = TimelineGeometry(width: width, duration: duration)
                for fraction in stride(from: 0.0, through: 1.0, by: 0.05) {
                    let px = width * fraction
                    let back = g.x(atTime: g.time(atX: px))
                    #expect(abs(back - px) <= 1e-9 * Swift.max(1, px),
                            "round trip lost \(px) at \(width)×\(duration): got \(back)")
                }
            }
        }
    }

    /// The same property under hostile input, deterministically, the way `TrimTests` fuzzes `Trim`.
    @Test func fuzzNeverLeavesTheRecordingAndNeverGoesNonFinite() {
        let widths: [Double] = [0, 1, 13, 106, 212, 760, 1e6, -4, .nan]
        let durations: [Double] = [0, 0.001, 0.2, 7.5, 90, 86_400, -3, .nan]
        let points: [Double] = [.nan, .infinity, -.infinity, -1e18, 1e18, -70, 0, 0.5, 105, 380, 759, 760, 1e9]
        var rng = LCG(seed: 0x7111_E11E)

        for width in widths {
            for duration in durations {
                let g = TimelineGeometry(width: width, duration: duration)
                #expect(g.width >= TimelineGeometry.minimumWidth && g.width.isFinite)
                #expect(g.duration >= 0 && g.duration.isFinite)
                for _ in 0..<2_000 {
                    let px = points.randomElement(using: &rng)!
                    let t = g.time(atX: px)
                    #expect(t.isFinite, "time went non-finite at \(px)")
                    #expect(t >= 0 && t <= g.duration, "time left the Recording: \(t)")
                    #expect(g.x(atTime: t).isFinite, "x went non-finite at \(t)")

                    let box = g.centredBoxX(at: t, boxWidth: 212)
                    #expect(box.isFinite && box >= 0 && box <= g.width,
                            "the loupe left the lane: \(box) at width \(g.width)")

                    let label = g.labelX(at: t, reserving: 30)
                    #expect(label.isFinite && label >= 0 && label <= g.width,
                            "a label left the lane: \(label) at width \(g.width)")
                }
            }
        }
    }

    // MARK: - The clamp that used to invert

    /// The review's "the `x` clamp inverts when `width < 212`", made into cases.
    @Test func theLoupeNeverLeavesALaneNarrowerThanItself() {
        let boxWidth = 212.0
        for width in [1.0, 40.0, 100.0, 105.0, 211.0, 212.0] {
            let g = TimelineGeometry(width: width, duration: 90)
            for t in [0.0, 22.5, 45.0, 67.5, 90.0] {
                let x = g.centredBoxX(at: t, boxWidth: boxWidth)
                #expect(x >= 0, "the loupe went off the leading edge: \(x) at width \(width)")
                #expect(x <= width, "the loupe went off the trailing edge: \(x) at width \(width)")
                // Too narrow to avoid both edges: it overhangs symmetrically rather than picking one.
                #expect(abs(x - width / 2) < 1e-9, "the loupe did not centre at width \(width)")
            }
        }
    }

    /// Wide enough to fit, it tracks the handle and stops exactly half a box from each edge.
    @Test func theLoupeTracksOnceTheLaneCanHoldIt() {
        let g = TimelineGeometry(width: 760, duration: 90)
        #expect(g.centredBoxX(at: 0, boxWidth: 212) == 106)
        #expect(g.centredBoxX(at: 90, boxWidth: 212) == 760 - 106)
        #expect(abs(g.centredBoxX(at: 45, boxWidth: 212) - 380) < 1e-9)
        #expect(g.centredBoxX(at: 45, boxWidth: 0) == g.x(atTime: 45))
    }

    /// The ruler's last label is pulled in so it cannot run off the trailing edge — and, unlike the
    /// old one-sided `min`, cannot run off the leading one either.
    @Test func aLabelIsPulledInsideTheLane() {
        #expect(lane.labelX(at: 90, reserving: 30) == 730)
        #expect(abs(lane.labelX(at: 45, reserving: 30) - 380) < 1e-9)
        #expect(lane.labelX(at: -100, reserving: 30) == 0)
        #expect(TimelineGeometry(width: 10, duration: 90).labelX(at: 90, reserving: 30) == 0)
    }

    // MARK: - Dropout bands

    /// A Dropout that is sub-pixel on an always-fits-the-width lane still has to be visible.
    @Test func aSubPixelDropoutKeepsItsFloor() {
        #expect(lane.points(from: 10, to: 10.0001, minimum: 3) == 3)
        #expect(abs(lane.points(from: 0, to: 45, minimum: 3) - 380) < 1e-9)
        // The loupe asks for no floor, because it exists to show raw detail.
        #expect(lane.points(from: 10, to: 10, minimum: 0) == 0)
    }

    // MARK: - Hit-testing

    /// A fixed fraction of the lane, not a fixed number of seconds, so the grab area is the same
    /// physical size whatever the Recording's length.
    @Test func theGrabToleranceIsAConstantFractionOfTheLane() {
        for duration in [0.5, 30.0, 90.0, 3600.0] {
            let g = TimelineGeometry(width: 760, duration: duration)
            #expect(abs(g.grabTolerance - duration * 0.02) < 1e-12)
            #expect(abs(g.x(atTime: g.grabTolerance) - 760 * 0.02) < 1e-9,
                    "the grab radius is not 2% of the lane at \(duration)s")
        }
    }

    // MARK: - The ruler's ladder

    /// No duration means no ticks, not one tick at zero.
    @Test func anEmptyRecordingGetsNoTicks() {
        #expect(TimelineGeometry(width: 760, duration: 0).ticks.isEmpty)
        #expect(TimelineGeometry(width: 760, duration: -5).ticks.isEmpty)
        #expect(TimelineGeometry(width: 760, duration: .nan).ticks.isEmpty)
    }

    /// the rule, which had never been asserted: no two labels within 64 pt, wherever the
    /// ladder has a preset row that can deliver it.
    @Test func noTwoTickLabelsComeWithinTheMinimumSpacing() {
        for width in [212.0, 400.0, 760.0, 1200.0, 2400.0] {
            for duration in [0.5, 3, 12, 45, 90, 240, 900, 3600, 7200, 86_400.0] {
                let g = TimelineGeometry(width: width, duration: duration)
                guard g.tickInterval != TimelineGeometry.tickCandidates.last! else { continue }
                let xs = g.ticks.map { g.x(atTime: $0) }
                for (a, b) in zip(xs, xs.dropFirst()) {
                    #expect(b - a >= TimelineGeometry.minimumTickSpacing - 1e-9,
                            "labels \(a) and \(b) collide at \(width)×\(duration)")
                }
            }
        }
    }

    /// A known limit, pinned rather than hidden. the ladder stops at an hour, so a Recording
    /// long enough that even hourly ticks crowd — an adopted file of about 56 minutes per point
    /// of lane, so roughly 3 hours 20 at the editor's 212 pt minimum — gets ticks closer together
    /// than the 64 pt the ADR asks for.
    @Test func theLadderSaturatesRatherThanClimbingPastAnHour() {
        let crowded = TimelineGeometry(width: 212, duration: 86_400)
        #expect(crowded.tickInterval == 3600)
        let xs = crowded.ticks.map { crowded.x(atTime: $0) }
        let gap = xs[1] - xs[0]
        #expect(gap < TimelineGeometry.minimumTickSpacing,
                "the limit this test documents has gone away — tighten the assertion above")
    }

    /// The interval always comes off the ladder, and never climbs past its top.
    @Test func theIntervalIsAlwaysARungOfTheLadder() {
        for duration in [0.5, 30, 90, 3600, 86_400, 1e7] {
            let g = TimelineGeometry(width: 760, duration: duration)
            #expect(TimelineGeometry.tickCandidates.contains(g.tickInterval),
                    "\(g.tickInterval) is not on the ladder")
        }
        // Past the top preset row there is nothing better to pick, so it saturates rather than trapping.
        #expect(TimelineGeometry(width: 760, duration: 1e7).tickInterval
                == TimelineGeometry.tickCandidates.last!)
    }

    @Test func theTicksRunFromZeroAndNeverPassTheEnd() {
        let ticks = lane.ticks
        #expect(ticks.first == 0)
        #expect(ticks.allSatisfy { $0 <= lane.duration + 1e-9 })
        #expect(ticks == [0, 10, 20, 30, 40, 50, 60, 70, 80, 90])  // 90 s across 760 pt: the 10 s presetRow
    }

    // MARK: - Columns

    /// One column per point, so the waveform always fits the width.
    @Test func thereIsOneColumnPerPoint() {
        #expect(lane.columnCount == 760)
        #expect(TimelineGeometry(width: 0, duration: 90).columnCount == 1)
        #expect(TimelineGeometry(width: 212.7, duration: 90).columnCount == 212)
    }
}

/// A tiny deterministic generator, so the fuzz reproduces exactly and needs no clock.
private struct LCG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
