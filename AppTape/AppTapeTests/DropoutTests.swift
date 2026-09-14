//
//  DropoutTests.swift
//  AppTapeTests
//

import Testing
@testable import AppTape

/// Dropouts are recorded always; only ones a listener would notice are surfaced. The threshold is a
/// single Dropout of 250 ms **or a total of** 250 ms (ADR-0010).
struct DropoutTests {
    private let rate = 48_000.0
    private func frames(_ ms: Double) -> Int { Int(ms / 1000 * rate) }

    @Test func noDropoutsIsNotSurfaced() {
        #expect(DropoutSurfacing.isSurfaced([], sampleRate: rate) == false)
    }

    @Test func aSingleSubThresholdDropoutIsNotSurfaced() {
        // A dropped buffer: ~10.67 ms, well under 250 ms.
        let dropouts = [Dropout(start: 1000, frames: frames(10.67), cause: .overrun)]
        #expect(DropoutSurfacing.isSurfaced(dropouts, sampleRate: rate) == false)
    }

    @Test func aSingleDropoutAtOrAboveThresholdIsSurfaced() {
        let dropouts = [Dropout(start: 0, frames: frames(250), cause: .rebuild)]
        #expect(DropoutSurfacing.isSurfaced(dropouts, sampleRate: rate))

        let longer = [Dropout(start: 0, frames: frames(1000), cause: .rebuild)]
        #expect(DropoutSurfacing.isSurfaced(longer, sampleRate: rate))
    }

    @Test func scatteredMicroGapsSurfaceOnTheTotalRule() {
        // Fifty scattered ~6 ms gaps — none individually surfaces, but they add to 300 ms.
        let dropouts = (0..<50).map { Dropout(start: $0 * 10_000, frames: frames(6), cause: .overrun) }
        #expect(dropouts.allSatisfy { Double($0.frames) < DropoutSurfacing.thresholdSeconds * rate })
        #expect(DropoutSurfacing.isSurfaced(dropouts, sampleRate: rate))
    }

    @Test func justUnderTheTotalDoesNotSurface() {
        // Two 100 ms gaps total 200 ms — under 250 ms, and neither is individually over.
        let dropouts = [Dropout(start: 0, frames: frames(100), cause: .overrun),
                     Dropout(start: 5000, frames: frames(100), cause: .overrun)]
        #expect(DropoutSurfacing.isSurfaced(dropouts, sampleRate: rate) == false)
    }

    @Test func totalSecondsSumsEveryDropout() {
        let dropouts = [Dropout(start: 0, frames: frames(100), cause: .overrun),
                     Dropout(start: 5000, frames: frames(150), cause: .rebuild)]
        #expect(abs(DropoutSurfacing.totalSeconds(dropouts, sampleRate: rate) - 0.250) < 1e-6)
    }
}
