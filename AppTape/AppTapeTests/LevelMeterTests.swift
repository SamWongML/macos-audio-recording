//
//  LevelMeterTests.swift
//  AppTapeTests
//

import Foundation
import Testing
@testable import AppTape

/// The per-row level meter's mapping (issue #59). The property the acceptance criterion turns
/// on is the boundary: a dead tap reads *exactly* zero.
struct LevelMeterTests {
    @Test func aDeadTapReadsExactlyZero() {
        #expect(LevelMeter.fill(forLinearPeak: nil) == 0)   // no tap
        #expect(LevelMeter.fill(forLinearPeak: 0) == 0)     // all-zero chunk (soft fault)
    }

    @Test func aPeakBelowTheFloorReadsZero() {
        #expect(LevelMeter.fill(forLinearPeak: -0.5) == 0)          // guarded non-positive
        #expect(LevelMeter.fill(forLinearPeak: 0.0005) == 0)        // ~-66 dBFS, under the floor
        #expect(LevelMeter.fill(forLinearPeak: 0.0001) == 0)        // ~-80 dBFS, well under
    }

    @Test func fullScaleReadsOne() {
        #expect(LevelMeter.fill(forLinearPeak: 1.0) == 1.0)
    }

    @Test func pastFullScaleClampsAtOne() {
        #expect(LevelMeter.fill(forLinearPeak: 2.0) == 1.0)
    }

    @Test func halfScaleInDecibelsReadsAboutAHalf() {
        // -30 dBFS is the midpoint of the -60 dB floor-to-ceiling ramp.
        let half = LevelMeter.fill(forLinearPeak: Float(pow(10.0, -30.0 / 20.0)))
        #expect(abs(half - 0.5) < 0.01)
    }

    @Test func theRampIsMonotonic() {
        #expect(LevelMeter.fill(forLinearPeak: 0.01) < LevelMeter.fill(forLinearPeak: 0.1))
        #expect(LevelMeter.fill(forLinearPeak: 0.1) < LevelMeter.fill(forLinearPeak: 0.5))
        #expect(LevelMeter.fill(forLinearPeak: 0.5) < LevelMeter.fill(forLinearPeak: 1.0))
    }

    // MARK: - Publish or hold (issue #100)
    //
    // The engine drains far faster than audio arrives — a 5 ms nap on an empty ring against
    // ~170 ms of audio per real chunk — so whether an empty drain may zero the published level
    // is the whole difference between a live meter and a dead one.

    @Test func aRealChunkPublishesItsPeak() {
        let decision = LevelMeter.publication(producedSamples: 1024, peak: 0.7,
                                              now: 100, lastPublishedAt: 99.9)
        #expect(decision == .publish(0.7))
    }

    @Test func anEmptyDrainHoldsTheLastPeakRatherThanZeroingIt() {
        // The defect in one assertion: this used to publish 0, ~30 times per real chunk.
        let decision = LevelMeter.publication(producedSamples: 0, peak: 0,
                                              now: 100, lastPublishedAt: 99.99)
        #expect(decision == .hold)
    }

    @Test func aFamineReadsZeroOnceTheHoldExpires() {
        let decision = LevelMeter.publication(producedSamples: 0, peak: 0,
                                              now: 100, lastPublishedAt: 100 - LevelMeter.holdSeconds)
        #expect(decision == .publish(0))
    }

    @Test func aSoftFaultedTapReadsZeroImmediately() {
        // An all-zero chunk is still a chunk: `producedSamples > 0` with a zero peak, so it
        // publishes at once rather than waiting out the hold. This is the contract's other half.
        let decision = LevelMeter.publication(producedSamples: 1024, peak: 0,
                                              now: 100, lastPublishedAt: 99.99)
        #expect(decision == .publish(0))
    }

    @Test func theHoldOutlastsTheGapBetweenRealChunks() {
        // A real chunk carries ~170 ms; the hold has to be longer or an ordinary gap reads as
        // silence, which is the bug wearing a smaller number.
        #expect(LevelMeter.holdSeconds > 0.17)
    }
}
