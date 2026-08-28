//
//  LoudnessExportTests.swift
//  AppTapeTests
//

import AVFoundation
import AudioToolbox
import Testing
import Foundation
@testable import AppTape

/// The normalized Export path end to end (ADR-0013): the encode measures the trimmed range, applies
/// one clamped gain, and — with manual Gain on top — a single combined multiply, never a second
/// normalization pass. The lossless Master preset is used on purpose: the written file's loudness is
/// the input's, scaled, so re-measuring it proves *where* the correction landed to within a fraction
/// of a LU. A steady tone at −6 LUFS has ample ceiling and cap room, so nothing clamps.
struct LoudnessExportTests {
    /// A stereo tone whose integrated loudness clears the gates and leaves the ceiling slack.
    private func writeTone(at url: URL, seconds: Double = 2, amplitude: Double = 0.5,
                           frequency: Double = 1000) throws {
        let asbd = AudioStreamBasicDescription(
            mSampleRate: 48_000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 8, mFramesPerPacket: 1, mBytesPerFrame: 8,
            mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)
        let writer = try CAFMasterWriter(url: url, asbd: asbd, sourceName: "Tone")
        let frames = Int(seconds * 48_000)
        var samples = [Float](repeating: 0, count: frames * 2)
        for f in 0..<frames {
            let v = Float(amplitude * sin(2 * .pi * frequency * Double(f) / 48_000))
            samples[f * 2] = v
            samples[f * 2 + 1] = v
        }
        try samples.withUnsafeBufferPointer { try writer.write($0) }
        writer.close()
    }

    private func integrated(of url: URL) throws -> Double {
        let file = try AVAudioFile(forReading: url)
        let measurement = try LoudnessMeter.measure(url: url, startFrame: 0, frameCount: file.length)
        return try #require(measurement.integratedLUFS)
    }

    private func exportMaster(_ source: URL, to dest: URL, normalize: Bool, gainDB: Double = 0) throws {
        let file = try AVAudioFile(forReading: source)
        let request = ExportRequest(source: source, destination: dest,
                                    startFrame: 0, frameCount: file.length, preset: .master,
                                    normalize: normalize, gainDB: gainDB)
        try ExportEncoder().run(request) { _ in }
    }

    @Test func normalizingLandsTheExportNearTheMinusSixteenTarget() throws {
        let dir = try AudioFixtures.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("master.caf")
        try writeTone(at: source)
        let dest = dir.appendingPathComponent("normalized.m4a")

        try exportMaster(source, to: dest, normalize: true)
        #expect(abs(try integrated(of: dest) - LoudnessTarget.integratedLUFS) < 0.5)
    }

    @Test func manualGainRidesOnTopAsOneCombinedMultiply() throws {
        // Correction brings the tone to −16; +3 dB Gain rides on top → −13. That the result is the
        // target *plus* the Gain (not the target re-normalized) is what "no double-normalize" means.
        let dir = try AudioFixtures.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("master.caf")
        try writeTone(at: source)
        let dest = dir.appendingPathComponent("gained.m4a")

        try exportMaster(source, to: dest, normalize: true, gainDB: 3)
        #expect(abs(try integrated(of: dest) - (LoudnessTarget.integratedLUFS + 3)) < 0.5)
    }

    @Test func aFaithfulExportLeavesLoudnessUntouched() throws {
        // Normalization off, Gain 0: the written file's loudness is the source's, unchanged.
        let dir = try AudioFixtures.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("master.caf")
        try writeTone(at: source)
        let dest = dir.appendingPathComponent("faithful.m4a")

        try exportMaster(source, to: dest, normalize: false)
        #expect(abs(try integrated(of: dest) - (try integrated(of: source))) < 0.3)
    }

    @Test func aSilentRangeStillExportsWithNoCorrection() throws {
        // Undefined loudness → 0 dB correction, and Export still completes (ADR-0013).
        let dir = try AudioFixtures.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("silent.caf")
        try writeTone(at: source, seconds: 1, amplitude: 0)   // pure silence
        let dest = dir.appendingPathComponent("silent.m4a")

        try exportMaster(source, to: dest, normalize: true)
        let out = try AVAudioFile(forReading: dest)
        #expect(out.length > 0)                                        // a real, decodable file
        #expect(abs(Double(out.length) / out.fileFormat.sampleRate - 1.0) < 0.1)   // ~1 s
    }
}
