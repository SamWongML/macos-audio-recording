//
//  SeamTests.swift
//  AppTapeTests
//

import Testing
@testable import AppTape

/// Seams are recorded always; only ones a listener would notice are surfaced. The threshold is a
/// single Seam of 250 ms **or a total of** 250 ms (ADR-0010).
struct SeamTests {
    private let rate = 48_000.0
    private func frames(_ ms: Double) -> Int { Int(ms / 1000 * rate) }

    @Test func noSeamsIsNotSurfaced() {
        #expect(SeamSurfacing.isSurfaced([], sampleRate: rate) == false)
    }

    @Test func aSingleSubThresholdSeamIsNotSurfaced() {
        // A dropped buffer: ~10.67 ms, well under 250 ms.
        let seams = [Seam(start: 1000, frames: frames(10.67), cause: .overrun)]
        #expect(SeamSurfacing.isSurfaced(seams, sampleRate: rate) == false)
    }

    @Test func aSingleSeamAtOrAboveThresholdIsSurfaced() {
        let seams = [Seam(start: 0, frames: frames(250), cause: .rebuild)]
        #expect(SeamSurfacing.isSurfaced(seams, sampleRate: rate))

        let longer = [Seam(start: 0, frames: frames(1000), cause: .rebuild)]
        #expect(SeamSurfacing.isSurfaced(longer, sampleRate: rate))
    }

    @Test func scatteredMicroGapsSurfaceOnTheTotalRule() {
        // Fifty scattered ~6 ms gaps — none individually surfaces, but they add to 300 ms.
        let seams = (0..<50).map { Seam(start: $0 * 10_000, frames: frames(6), cause: .overrun) }
        #expect(seams.allSatisfy { Double($0.frames) < SeamSurfacing.thresholdSeconds * rate })
        #expect(SeamSurfacing.isSurfaced(seams, sampleRate: rate))
    }

    @Test func justUnderTheTotalDoesNotSurface() {
        // Two 100 ms gaps total 200 ms — under 250 ms, and neither is individually over.
        let seams = [Seam(start: 0, frames: frames(100), cause: .overrun),
                     Seam(start: 5000, frames: frames(100), cause: .overrun)]
        #expect(SeamSurfacing.isSurfaced(seams, sampleRate: rate) == false)
    }

    @Test func totalSecondsSumsEverySeam() {
        let seams = [Seam(start: 0, frames: frames(100), cause: .overrun),
                     Seam(start: 5000, frames: frames(150), cause: .rebuild)]
        #expect(abs(SeamSurfacing.totalSeconds(seams, sampleRate: rate) - 0.250) < 1e-6)
    }
}
