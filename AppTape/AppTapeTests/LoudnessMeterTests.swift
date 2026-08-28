//
//  LoudnessMeterTests.swift
//  AppTapeTests
//

import Testing
import Foundation
@testable import AppTape

/// The hand-rolled BS.1770-5 pass (ADR-0013), driven through the streaming `LoudnessAnalyzer` seam
/// with engineered fixtures. The absolute anchor is the standard calibration a hand-derivation of the
/// K-weighting confirms: a 0 dBFS 1 kHz sine reads −3.0 LUFS in one channel. The relative anchors are
/// filter-independent by construction — halving amplitude is exactly −6.02 LU, and a matched stereo
/// pair is exactly +3.01 LU over the same single channel — so they hold regardless of the exact gain.
struct LoudnessMeterTests {
    private let sampleRate = 48_000.0

    /// `seconds` of a sine at `frequency`, `amplitude`, `channels` identical channels, plus a phase.
    private func sine(seconds: Double, frequency: Double = 1000, amplitude: Double = 1.0,
                      channels: Int = 1, phase: Double = 0) -> [Float] {
        let frames = Int(seconds * sampleRate)
        var out = [Float](repeating: 0, count: frames * channels)
        for f in 0..<frames {
            let v = Float(amplitude * sin(2 * .pi * frequency * Double(f) / sampleRate + phase))
            for c in 0..<channels { out[f * channels + c] = v }
        }
        return out
    }

    private func measure(_ interleaved: [Float], channels: Int) -> LoudnessMeasurement {
        let analyzer = LoudnessAnalyzer(sampleRate: sampleRate, channels: channels)
        interleaved.withUnsafeBufferPointer {
            analyzer.process($0.baseAddress!, frameCount: $0.count / channels)
        }
        return analyzer.finish()
    }

    // MARK: - Integrated loudness

    @Test func aFullScaleMonoSineReadsAboutMinusThreeLUFS() {
        let m = measure(sine(seconds: 2, amplitude: 1.0, channels: 1), channels: 1)
        let lufs = try! #require(m.integratedLUFS)
        #expect(abs(lufs - (-3.0)) < 0.5)   // BS.1770 calibration: 0 dBFS 1 kHz sine ≈ −3.0 LUFS
    }

    @Test func halvingAmplitudeDropsLoudnessBySixDecibels() {
        let loud = try! #require(measure(sine(seconds: 2, amplitude: 0.5), channels: 1).integratedLUFS)
        let quiet = try! #require(measure(sine(seconds: 2, amplitude: 0.25), channels: 1).integratedLUFS)
        #expect(abs((loud - quiet) - 6.02) < 0.1)   // a −6 dB amplitude change is −6.02 LU, filter-independent
    }

    @Test func matchedStereoIsThreeDecibelsLouderThanTheSameMono() {
        let mono = try! #require(measure(sine(seconds: 2, amplitude: 0.5, channels: 1), channels: 1).integratedLUFS)
        let stereo = try! #require(measure(sine(seconds: 2, amplitude: 0.5, channels: 2), channels: 2).integratedLUFS)
        #expect(abs((stereo - mono) - 3.01) < 0.1)   // two matched channels sum to +3.01 LU
    }

    // MARK: - The relative gate

    @Test func theRelativeGateExcludesTrailingSilence() {
        // 1 s of a loud sine then 1 s of silence: the gate must report the loud part's loudness, not
        // the −3 dB average of loud-plus-silence. Silence sits under the −70 LKFS absolute gate.
        let loud = sine(seconds: 1, amplitude: 0.5, channels: 1)
        let silence = [Float](repeating: 0, count: Int(sampleRate) )
        let mixed = loud + silence

        let gated = try! #require(measure(mixed, channels: 1).integratedLUFS)
        let loudOnly = try! #require(measure(loud, channels: 1).integratedLUFS)
        #expect(abs(gated - loudOnly) < 1.0)          // gating recovers the loud portion
        #expect(gated > loudOnly - 1.0)               // and is far above the naive ~−3 dB average
    }

    // MARK: - Unmeasurable ranges (ADR-0013: 0 dB, Export still completes)

    @Test func pureSilenceHasNoMeasurableLoudness() {
        let m = measure([Float](repeating: 0, count: Int(2 * sampleRate)), channels: 1)
        #expect(m.integratedLUFS == nil)
        #expect(m.truePeakDBTP == -.infinity)
    }

    @Test func aRangeShorterThanOneGatingBlockIsUnmeasurable() {
        // 0.3 s is three 100 ms sub-blocks — no complete 400 ms block can form.
        let m = measure(sine(seconds: 0.3, amplitude: 0.5), channels: 1)
        #expect(m.integratedLUFS == nil)
    }

    // MARK: - True peak (4× oversampled, dBTP)

    @Test func aHalfScaleSineTruePeakIsAboutMinusSixDBTP() {
        let m = measure(sine(seconds: 1, amplitude: 0.5), channels: 1)
        #expect(abs(m.truePeakDBTP - (-6.02)) < 0.5)
    }

    @Test func oversamplingCatchesAnInterSamplePeakTheSamplesMiss() {
        // A 12 kHz (fs/4) full-scale sine at 45°: every sample lands at ±0.707 (a −3.01 dBFS sample
        // peak), but the continuous waveform crests at 1.0. Oversampling must see over −3 dB.
        let m = measure(sine(seconds: 0.5, frequency: 12_000, amplitude: 1.0, phase: .pi / 4), channels: 1)
        #expect(m.truePeakDBTP > -1.5)                // recovers close to 0 dBTP
        #expect(m.truePeakDBTP > -3.01 + 1.0)         // clearly above the sample peak
    }
}
