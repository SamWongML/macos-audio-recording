//
//  AudioFixtures.swift
//  AppTapeTests
//

import AVFoundation
import AudioToolbox
import Foundation
@testable import AppTape

/// Real CAF masters for the tests that need a readable Recording on disk — the store and the
/// metadata round-trip both go through `Recording.init?`, which opens the file with `AVAudioFile`.
enum AudioFixtures {
    private static func stereoFloat32(_ sampleRate: Double = 48_000) -> AudioStreamBasicDescription {
        AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 8, mFramesPerPacket: 1, mBytesPerFrame: 8,
            mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)
    }

    /// A `.caf` of `seconds` of a 440 Hz tone at `url`. Writes the Source xattr like capture does.
    @discardableResult
    static func writeCAF(at url: URL, seconds: Double = 1.0, source: String = "Test Source") throws -> URL {
        let writer = try CAFMasterWriter(url: url, asbd: stereoFloat32(), sourceName: source)
        let frames = Int(seconds * 48_000)
        var samples = [Float](repeating: 0, count: frames * 2)
        for f in 0..<frames {
            let v = Float(sin(2 * Double.pi * 440 * Double(f) / 48_000)) * 0.5
            samples[f * 2] = v
            samples[f * 2 + 1] = v
        }
        try samples.withUnsafeBufferPointer { try writer.write($0) }
        writer.close()
        return url
    }

    /// A fresh empty scratch directory the caller is responsible for removing.
    static func makeScratchDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("apptape-lib-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
