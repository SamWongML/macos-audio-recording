//
//  CAFMasterWriterTests.swift
//  AppTapeTests
//

import Testing
import AVFoundation
import AudioToolbox
@testable import AppTape

/// The write path is where the crash guarantee lives, so it is exercised end to end against
/// real Core Audio: a written master must be a valid, playable CAF, carry its Source, and be
/// readable *before* it is closed (ADR-0003, ADR-0006).
struct CAFMasterWriterTests {
    /// Interleaved Float32 stereo at 48 kHz — the tap's delivered format (issue #12).
    private func stereoFloat32(_ sampleRate: Double = 48_000) -> AudioStreamBasicDescription {
        AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 8, mFramesPerPacket: 1, mBytesPerFrame: 8,
            mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)
    }

    /// One second of a 440 Hz tone, interleaved stereo.
    private func tone(frames: Int) -> [Float] {
        var samples = [Float](repeating: 0, count: frames * 2)
        for f in 0..<frames {
            let v = Float(sin(2 * Double.pi * 440 * Double(f) / 48_000)) * 0.5
            samples[f * 2] = v
            samples[f * 2 + 1] = v
        }
        return samples
    }

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("apptape-test-\(UUID().uuidString).caf")
    }

    @Test func writesAPlayableCAFWithTheRightFramesAndSource() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let writer = try CAFMasterWriter(url: url, asbd: stereoFloat32(), sourceName: "Google Chrome")
        let block = tone(frames: 4_800)   // 0.1 s
        for _ in 0..<5 { try block.withUnsafeBufferPointer { try writer.write($0) } }
        #expect(writer.framesWritten == 24_000)
        writer.close()

        // Reopens as an ordinary CAF, all frames present.
        let read = try AVAudioFile(forReading: url)
        #expect(read.length == 24_000)
        #expect(read.processingFormat.channelCount == 2)
        #expect(read.fileFormat.sampleRate == 48_000)

        // The Source rode along in an extended attribute.
        #expect(RecordingMetadata.readSource(from: url) == "Google Chrome")
    }

    @Test func aNotYetClosedFileIsAlreadyReadable() throws {
        // Stands in for the crash property: with deferred size updates and CAF's negative
        // mChunkSize, a file whose header was never finalized still opens and reports its
        // frames from the bytes on disk.
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let writer = try CAFMasterWriter(url: url, asbd: stereoFloat32(), sourceName: "Safari")
        let block = tone(frames: 4_800)
        for _ in 0..<5 { try block.withUnsafeBufferPointer { try writer.write($0) } }
        // Deliberately NOT closing the writer — simulate the process dying mid-capture.

        var readID: AudioFileID?
        let status = AudioFileOpenURL(url as CFURL, .readPermission, kAudioFileCAFType, &readID)
        #expect(status == noErr)
        let file = try #require(readID)
        defer { AudioFileClose(file) }

        var packetCount: Int64 = 0
        var size = UInt32(MemoryLayout<Int64>.size)
        let query = AudioFileGetProperty(file, kAudioFilePropertyAudioDataPacketCount, &size, &packetCount)
        #expect(query == noErr)
        // The header was never finalized, yet the frames are recoverable from the file.
        #expect(packetCount > 0)
        #expect(packetCount <= 24_000)

        writer.close()
    }

    @Test func writesWhateverFormatTheTapReports() throws {
        // Not assumed to be 48 kHz: a 44.1 kHz tap format is written verbatim (ADR-0003).
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let writer = try CAFMasterWriter(url: url, asbd: stereoFloat32(44_100), sourceName: "Music")
        let block = tone(frames: 4_410)
        try block.withUnsafeBufferPointer { try writer.write($0) }
        writer.close()

        let read = try AVAudioFile(forReading: url)
        #expect(read.fileFormat.sampleRate == 44_100)
        #expect(read.length == 4_410)
    }
}
