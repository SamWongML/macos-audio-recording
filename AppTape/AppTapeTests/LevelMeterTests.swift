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
}
