//
//  TrimTests.swift
//  AppTapeTests
//

import Testing
import Foundation
@testable import AppTape

/// `Trim` makes invalid states unrepresentable (ADR-0006, issue #7). These pin the three
/// invariants — handles never cross, the 0.2 s minimum, and no `NaN` reaching the xattr —
/// with worked examples and then with a deterministic fuzz over millions of reachable states.
struct TrimTests {
    // The four failure classes the ad-hoc clamping produced, each now a valid Trim instead.

    @Test func startCannotBePushedPastTheEnd() {
        var trim = Trim(start: 29.9, end: 29.95, duration: 30)
        trim.setStart(29.95)              // aim the start at (and past) the end
        #expect(trim.start <= trim.end - Trim.minimumLength + 1e-9)
        #expect(trim.end == 29.95)        // the end did not move to make room
    }

    @Test func endCannotBePulledBeforeTheStart() {
        var trim = Trim(start: 10, end: 20, duration: 30)
        trim.setEnd(5)
        #expect(trim.end >= trim.start + Trim.minimumLength - 1e-9)
        #expect(trim.start == 10)
    }

    @Test func neitherHandleLeavesTheFile() {
        var trim = Trim(duration: 30)
        trim.setStart(-100)
        trim.setEnd(1000)
        #expect(trim.start == 0)
        #expect(trim.end == 30)
    }

    @Test func theMinimumLengthIsPreservedFromBothSides() {
        var fromStart = Trim(duration: 30)
        fromStart.setStart(200)           // shove the start far right
        #expect(abs(fromStart.length - Trim.minimumLength) < 1e-9)
        #expect(fromStart.end == 30)

        var fromEnd = Trim(duration: 30)
        fromEnd.setEnd(-200)              // shove the end far left
        #expect(abs(fromEnd.length - Trim.minimumLength) < 1e-9)
        #expect(fromEnd.start == 0)
    }

    // A Recording shorter than the minimum: the whole thing is the Trim, and it is fixed.
    // Reachable simply by pointing the app at a shorter file with the same name (ADR-0006).

    @Test func aRecordingShorterThanTheMinimumIsFixed() {
        var trim = Trim(duration: 0.1)
        #expect(trim.isFixed)
        #expect(trim.start == 0 && trim.end == 0.1)
        trim.setStart(0.05)               // no-op: nothing can move
        trim.setEnd(0.02)
        #expect(trim.start == 0 && trim.end == 0.1)
    }

    // NaN / ±inf are ignored rather than propagated into a handle — a single one written to the
    // xattr would break the Recording permanently on the next open.

    @Test func nonFiniteInputIsIgnored() {
        var trim = Trim(start: 5, end: 25, duration: 30)
        trim.setStart(.nan)
        trim.setEnd(.infinity)
        trim.setStart(-.infinity)
        trim.nudgeEnd(by: .nan)
        #expect(trim.start == 5 && trim.end == 25)
    }

    @Test func aNonFiniteDurationCollapsesToZeroRatherThanTrapping() {
        let trim = Trim(duration: .nan)
        #expect(trim.duration == 0)
        #expect(trim.isFixed)
    }

    @Test func theSanitisingInitNeverTrapsOnGarbage() {
        // The old xattr reader checked end > start then applied min(end, duration), which could
        // pull end below start and trap on `a...b`. This must land on a valid Trim instead.
        let trim = Trim(start: 100, end: -100, duration: 5)
        #expect(trim.start <= trim.end)
        #expect(trim.range.lowerBound <= trim.range.upperBound)   // would trap if crossed
    }

    @Test func resetRestoresTheFullRange() {
        var trim = Trim(start: 10, end: 20, duration: 30)
        trim.reset()
        #expect(trim.start == 0 && trim.end == 30)
        #expect(trim.isWholeRecording)
    }

    // MARK: - Fuzz

    /// Every reachable Trim satisfies the invariants. A deterministic LCG drives a mix of
    /// `setStart`/`setEnd`/`nudge`/`reset` with hostile inputs (`nan`, `±inf`, wild magnitudes)
    /// across a range of durations, several rounds of mutation deep. Deterministic so a failure
    /// reproduces and so the test does not depend on a clock.
    @Test func fuzzNeverViolatesTheInvariants() {
        let durations = [0.0, 0.05, 0.2, 0.5, 1.0, 30.0, 1200.0]
        let inputs: [Double] = [.nan, .infinity, -.infinity, -1e18, 1e18, -5, -0.3, -0.05,
                                0, 0.05, 0.1, 0.2, 0.5, 15, 29.9, 30, 1199.9, 1e9]
        var rng = LCG(seed: 0x5EED_1234)

        for duration in durations {
            for _ in 0..<40_000 {
                var trim = Trim(duration: duration)
                for _ in 0..<6 {
                    switch rng.next() % 5 {
                    case 0: trim.setStart(inputs.randomElement(using: &rng)!)
                    case 1: trim.setEnd(inputs.randomElement(using: &rng)!)
                    case 2: trim.nudgeStart(by: inputs.randomElement(using: &rng)!)
                    case 3: trim.nudgeEnd(by: inputs.randomElement(using: &rng)!)
                    default: trim.reset()
                    }
                    check(trim)
                }
            }
        }
    }

    private func check(_ trim: Trim) {
        #expect(trim.start.isFinite, "start went non-finite")
        #expect(trim.end.isFinite, "end went non-finite")
        #expect(trim.start >= -1e-9, "start left the file: \(trim.start)")
        #expect(trim.end <= trim.duration + 1e-9, "end left the file: \(trim.end) > \(trim.duration)")
        #expect(trim.start <= trim.end + 1e-9, "handles crossed: \(trim.start) > \(trim.end)")
        if trim.isFixed {
            #expect(trim.start == 0 && trim.end == trim.duration, "a fixed Trim moved")
        } else {
            #expect(trim.length >= Trim.minimumLength - 1e-9,
                    "Trim shorter than the minimum: \(trim.length)")
        }
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
