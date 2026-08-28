//
//  LoudnessCorrectionTests.swift
//  AppTapeTests
//

import Testing
import Foundation
@testable import AppTape

/// The single clamped gain (ADR-0013). Every expected number is worked from the fixed contract by
/// hand — target −16 LUFS, ceiling −3 dBTP, cap +12 dB — never recomputed the way `compute` does.
struct LoudnessCorrectionTests {
    private func measurement(_ lufs: Double?, peak: Double) -> LoudnessMeasurement {
        LoudnessMeasurement(integratedLUFS: lufs, truePeakDBTP: peak)
    }

    @Test func aQuietRangeIsAmplifiedTowardTheTargetWhenTheCeilingHasRoom() {
        // −24 LUFS wants +8 dB; peak at −20 dBTP has room to −3 (ceiling limit +17), so +8 lands full.
        let c = LoudnessCorrection.compute(for: measurement(-24, peak: -20))
        #expect(abs(c.decibels - 8.0) < 1e-9)
        #expect(c.landing == .full)
        #expect(c.caption == nil)
        #expect(c.figureText == "+8.0 dB")
    }

    @Test func aLoudRangeIsAttenuatedUncapped() {
        // −6 LUFS wants −10 dB; attenuation is uncapped and the ceiling has ample room.
        let c = LoudnessCorrection.compute(for: measurement(-6, peak: -1))
        #expect(abs(c.decibels - (-10.0)) < 1e-9)
        #expect(c.landing == .full)
    }

    @Test func amplificationIsCappedAtTwelveDecibels() {
        // −40 LUFS wants +24 dB but the cap holds it to +12; peak at −40 dBTP leaves the ceiling slack,
        // so the cap — not the ceiling — is what bound it.
        let c = LoudnessCorrection.compute(for: measurement(-40, peak: -40))
        #expect(abs(c.decibels - 12.0) < 1e-9)
        #expect(c.landing == .amplificationCapped)
        #expect(c.caption == "limited to keep the noise floor down")
        #expect(c.figureText == "+12.0 dB")
    }

    @Test func theCeilingClampsBelowTheDesiredGain() {
        // −24 LUFS wants +8 dB, but a peak at −6 dBTP only allows +3 to reach the −3 dBTP ceiling.
        let c = LoudnessCorrection.compute(for: measurement(-24, peak: -6))
        #expect(abs(c.decibels - 3.0) < 1e-9)
        #expect(c.landing == .ceilingReached)
        #expect(c.caption == "peak ceiling reached")
    }

    @Test func theCeilingBindsBeforeTheCapWhenBothWouldClamp() {
        // −40 LUFS wants +24 dB; the cap would allow +12 but a peak at −10 dBTP allows only +7,
        // so the ceiling is the tighter constraint and is what the caption names.
        let c = LoudnessCorrection.compute(for: measurement(-40, peak: -10))
        #expect(abs(c.decibels - 7.0) < 1e-9)
        #expect(c.landing == .ceilingReached)
    }

    @Test func aRangeCapturedHotterThanTheCeilingIsPulledDownEvenWhenItWantedABoost() {
        // −18 LUFS wants +2 dB, but a peak already at −1 dBTP is over the ceiling: clamp to −2 dB.
        let c = LoudnessCorrection.compute(for: measurement(-18, peak: -1))
        #expect(abs(c.decibels - (-2.0)) < 1e-9)
        #expect(c.landing == .ceilingReached)
        #expect(c.figureText == "−2.0 dB")
    }

    @Test func anUndefinedMeasurementGetsNoCorrection() {
        let c = LoudnessCorrection.compute(for: measurement(nil, peak: -.infinity))
        #expect(c.decibels == 0)
        #expect(c.landing == .undefined)
        #expect(c.figureText == "No correction")
        #expect(c.caption == "range too quiet to measure")
    }

    @Test func theThreeLandShortCaptionsAreDistinct() {
        let cap = LoudnessCorrection.compute(for: measurement(-40, peak: -40)).caption
        let ceiling = LoudnessCorrection.compute(for: measurement(-24, peak: -6)).caption
        let undefined = LoudnessCorrection.compute(for: measurement(nil, peak: -.infinity)).caption
        #expect(cap != nil && ceiling != nil && undefined != nil)
        #expect(Set([cap, ceiling, undefined]).count == 3)
    }

    @Test func composingCorrectionAndGainIsOneMultiply() {
        // gain(a) · gain(b) == gain(a + b): stacking never double-normalizes (ADR-0013).
        let composed = LoudnessCorrection.linearScalar(correctionDB: 4, gainDB: 0)
                     * LoudnessCorrection.linearScalar(correctionDB: 0, gainDB: 3)
        let combined = LoudnessCorrection.linearScalar(correctionDB: 4, gainDB: 3)
        #expect(abs(composed - combined) < 1e-5)
        // And the scalar is the plain decibel-to-linear of the sum.
        #expect(abs(Double(combined) - pow(10.0, 7.0 / 20.0)) < 1e-6)
    }
}
