//
//  ExportEncoderTests.swift
//  AppTapeTests
//

import AVFoundation
import AudioToolbox
import Testing
import Foundation
@testable import AppTape

/// The encode loop end to end (ADR-0012): a real CAF master in, a real `.m4a` out, decoded back and
/// checked. These are the tests that prove the seam actually produces files — the four presets pick
/// the codec, the trim range is honoured to the frame, nothing is resampled or downmixed, and
/// cancellation throws before touching the destination.
struct ExportEncoderTests {
    /// 3 s of broadband noise at 48 kHz stereo — incompressible, so the codec choice shows up as a
    /// real size difference (a pure tone would let ALAC predict it away and defeat the ordering).
    private func writeNoise(at url: URL, seconds: Double = 3.0) throws {
        let asbd = AudioStreamBasicDescription(
            mSampleRate: 48_000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 8, mFramesPerPacket: 1, mBytesPerFrame: 8,
            mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)
        let writer = try CAFMasterWriter(url: url, asbd: asbd, sourceName: "Noise")
        let frames = Int(seconds * 48_000)
        var samples = [Float](repeating: 0, count: frames * 2)
        var seed: UInt64 = 0x1234_5678
        for i in 0..<samples.count {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            samples[i] = Float(Int32(truncatingIfNeeded: seed >> 33)) / Float(Int32.max) * 0.5
        }
        try samples.withUnsafeBufferPointer { try writer.write($0) }
        writer.close()
    }

    private func fileSize(_ url: URL) -> Int {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? Int) ?? 0
    }

    @Test(arguments: [QualityPreset.master, .high, .standard, .compact])
    func eachPresetProducesADecodableM4AAtTheNativeStereoRate(_ preset: QualityPreset) throws {
        let dir = try AudioFixtures.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("master.caf")
        try writeNoise(at: source, seconds: 2)
        let dest = dir.appendingPathComponent("out.m4a")

        // Export the middle second: frames [0.5 s, 1.5 s) = 24_000 frames at 48 kHz.
        var lastProgress = 0.0
        let request = ExportRequest(source: source, destination: dest,
                                    startFrame: 24_000, frameCount: 48_000, preset: preset)
        try ExportEncoder().run(request) { lastProgress = $0 }

        #expect(abs(lastProgress - 1.0) < 1e-9)   // progress reaches 1.0

        let out = try AVAudioFile(forReading: dest)
        let asbd = out.fileFormat.streamDescription.pointee
        #expect(out.fileFormat.channelCount == 2)                 // no downmix
        #expect(abs(out.fileFormat.sampleRate - 48_000) < 1)      // no resample
        #expect(abs(Double(out.length) / out.fileFormat.sampleRate - 1.0) < 0.1)   // ~1 s trimmed

        switch preset {
        case .master:
            #expect(asbd.mFormatID == kAudioFormatAppleLossless)
        case .high, .standard:
            #expect(asbd.mFormatID == kAudioFormatMPEG4AAC)
        case .compact:
            #expect(asbd.mFormatID == kAudioFormatMPEG4AAC_HE, "compact format id = \(asbd.mFormatID) (aac=\(kAudioFormatMPEG4AAC) aach=\(kAudioFormatMPEG4AAC_HE))")
        }
    }

    @Test func lowerBitrateRungsProduceSmallerFilesOnIncompressibleAudio() throws {
        let dir = try AudioFixtures.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("master.caf")
        try writeNoise(at: source, seconds: 3)

        func size(_ preset: QualityPreset) throws -> Int {
            let dest = dir.appendingPathComponent("\(preset.rawValue).m4a")
            try ExportEncoder().run(ExportRequest(source: source, destination: dest,
                                                  startFrame: 0, frameCount: 48_000 * 3,
                                                  preset: preset)) { _ in }
            return fileSize(dest)
        }

        // Lossless noise is far larger than 64 kbps of it; the target bitrates order as chosen.
        let master = try size(.master), high = try size(.high)
        let standard = try size(.standard), compact = try size(.compact)
        #expect(master > high)
        #expect(high > standard)
        #expect(standard > compact)
        #expect(compact > 0)
    }

    @Test func anAlreadyCancelledEncodeThrowsAndNeverCompletes() throws {
        let dir = try AudioFixtures.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("master.caf")
        try writeNoise(at: source, seconds: 2)
        let dest = dir.appendingPathComponent("out.m4a")

        let encoder = ExportEncoder()
        encoder.cancel()
        #expect(throws: ExportEncoder.Failure.self) {
            try encoder.run(ExportRequest(source: source, destination: dest,
                                          startFrame: 0, frameCount: 96_000, preset: .high)) { _ in }
        }
    }

    @Test func anEmptyRangeIsRefused() throws {
        let dir = try AudioFixtures.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("master.caf")
        try writeNoise(at: source, seconds: 1)
        #expect(throws: ExportEncoder.Failure.self) {
            try ExportEncoder().run(ExportRequest(source: source,
                                                  destination: dir.appendingPathComponent("x.m4a"),
                                                  startFrame: 0, frameCount: 0, preset: .high)) { _ in }
        }
    }
}
