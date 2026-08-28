//
//  ExportEncoder.swift
//  AppTape
//

import AudioToolbox
import Foundation
import Synchronization

/// One export's parameters, snapshotted at launch (ADR-0012): the master to read, the temp file to
/// write, the trimmed frame range, the preset, and the Loudness/Gain settings — whether to normalize
/// Loudness and the manual Gain in dB (ADR-0013). A value, so later edits to Trim, preset, the toggle
/// or the Gain slider never reach a running encode. These two default to a **faithful export** (no
/// normalization, 0 dB Gain), so the plain path stays untouched.
struct ExportRequest {
    let source: URL
    let destination: URL
    let startFrame: Int64
    let frameCount: Int64
    let preset: QualityPreset
    /// When true, the encode first measures the trimmed range (BS.1770-5) and applies the clamped
    /// Loudness correction; when false, only the manual Gain applies (ADR-0013).
    var normalize: Bool = false
    /// The manual Gain offset in dB, always applied — it rides on top of any correction (ADR-0013).
    var gainDB: Double = 0
}

/// The encode itself: a **hand-rolled `ExtAudioFileRead`/`Write` loop** over the master's trimmed
/// frames (ADR-0012). Hand-rolled rather than an opaque `AVAssetExportSession` for one reason —
/// exact frame counts, so the inspector's progress bar shows real progress of the real file rather
/// than an estimate. It reads the master as Float32 through an `ExtAudioFile` client format and
/// writes the compressed `.m4a`, letting the framework's `AudioConverter` do the codec work with
/// **no resampler and no downmix** (the client format carries the source's own rate and channels).
///
/// This is the **Export/Loudness math seam** (ADR-0013): when `normalize` is set, `run` first makes
/// a **measure pass** over the same trimmed frames (a hand-rolled BS.1770-5 `LoudnessMeter`), folds
/// the clamped correction and the manual Gain into **one linear scalar**, and every sample the write
/// loop emits passes through `applyGain(_:)` — a single multiply, never a limiter, so composing the
/// two gains is one operation rather than two normalization passes. With `normalize` off and Gain at
/// 0 the scalar is exactly 1 and the loop writes the trimmed master bit-faithfully.
///
/// The measure and encode passes report through one `onProgress`, so a normalized Export shows one
/// continuous measure-then-encode bar (ADR-0012/-0013).
///
/// Realtime-unsafe by design and run at `.utility` off the main thread (ADR-0012): it never joins
/// the audio workgroup, so it cannot preempt a live capture's IOProc.
final class ExportEncoder: @unchecked Sendable {
    /// ~0.34 s of stereo 48 kHz per read — large enough to keep syscalls down, small enough that a
    /// cancel is honoured within a fraction of a second.
    private static let bufferFrames = 16_384

    /// The measure pass's share of the one continuous progress bar when normalizing — it reads every
    /// frame once, as the encode reads-and-writes every frame once, so a bit under half is honest.
    private static let measureFraction = 0.4

    /// The linear scalar the write loop multiplies every sample by, set in `run` before the loop.
    private var scale: Float = 1

    private let cancelledFlag = Atomic<Bool>(false)

    /// Requests cancellation. The loop notices at the next chunk boundary and throws `.cancelled`;
    /// the caller then discards the temp, leaving the destination untouched (ADR-0012).
    func cancel() { cancelledFlag.store(true, ordering: .releasing) }
    var isCancelled: Bool { cancelledFlag.load(ordering: .acquiring) }

    enum Failure: Error, CustomStringConvertible {
        case emptyRange
        case cancelled
        case coreAudio(stage: String, status: OSStatus)

        var description: String {
            switch self {
            case .emptyRange: return "There is nothing in the Trim to export."
            case .cancelled: return "Export cancelled."
            case .coreAudio(let stage, let status):
                return "Export failed while \(stage) (error \(status))."
            }
        }
    }

    /// Runs the encode synchronously, reporting a `0...1` fraction as frames are written. Throws on
    /// failure or cancellation. Disposing the destination `ExtAudioFile` before returning finalizes
    /// the `.m4a`, so a successful return means the temp file is complete and ready to be swapped in.
    func run(_ request: ExportRequest, onProgress: (Double) -> Void) throws {
        guard request.frameCount > 0 else { throw Failure.emptyRange }

        // MARK: Gain — measure (if normalizing) and fold the correction + Gain into one scalar.
        // The measure pass leads the one continuous bar (ADR-0013). An unmeasurable range yields a
        // 0 dB correction and the encode still completes.
        var correctionDB = 0.0
        let encodeStart: Double
        if request.normalize {
            if isCancelled { throw Failure.cancelled }
            let measurement = try LoudnessMeter.measure(
                url: request.source, startFrame: request.startFrame, frameCount: request.frameCount
            ) { onProgress($0 * Self.measureFraction) }
            correctionDB = LoudnessCorrection.compute(for: measurement).decibels
            encodeStart = Self.measureFraction
        } else {
            encodeStart = 0
        }
        scale = LoudnessCorrection.linearScalar(correctionDB: correctionDB, gainDB: request.gainDB)
        let encodeSpan = 1 - encodeStart

        // MARK: Source — read the master as interleaved Float32 at its own rate and channels.
        var sourceRef: ExtAudioFileRef?
        try check(ExtAudioFileOpenURL(request.source as CFURL, &sourceRef), "opening the Recording")
        guard let sourceRef else { throw Failure.coreAudio(stage: "opening the Recording", status: -1) }
        defer { ExtAudioFileDispose(sourceRef) }

        var sourceFormat = AudioStreamBasicDescription()
        var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try check(ExtAudioFileGetProperty(sourceRef, kExtAudioFileProperty_FileDataFormat,
                                          &formatSize, &sourceFormat), "reading the Recording's format")

        let channels = max(1, Int(sourceFormat.mChannelsPerFrame))
        let rate = sourceFormat.mSampleRate
        var client = AudioStreamBasicDescription.interleavedFloat(rate: rate, channels: channels)
        let clientSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try check(ExtAudioFileSetProperty(sourceRef, kExtAudioFileProperty_ClientDataFormat,
                                          clientSize, &client), "preparing to read")
        try check(ExtAudioFileSeek(sourceRef, request.startFrame), "seeking to the Trim")

        // MARK: Destination — the compressed .m4a at the temp path.
        let sourceMeta = SourceFormat(sampleRate: rate, channelCount: channels,
                                      bitsPerChannel: Int(sourceFormat.mBitsPerChannel))
        var fileFormat = request.preset.fileFormat(for: sourceMeta)
        var destRef: ExtAudioFileRef?
        try check(ExtAudioFileCreateWithURL(request.destination as CFURL, kAudioFileM4AType,
                                            &fileFormat, nil, AudioFileFlags.eraseFile.rawValue,
                                            &destRef), "creating the export file")
        guard let destRef else { throw Failure.coreAudio(stage: "creating the export file", status: -1) }
        defer { ExtAudioFileDispose(destRef) }

        try check(ExtAudioFileSetProperty(destRef, kExtAudioFileProperty_ClientDataFormat,
                                          clientSize, &client), "preparing to write")
        configureEncoder(destRef, preset: request.preset)

        // MARK: Loop — read a chunk, transform, write, report. Cancellable at each boundary.
        let bytesPerFrame = Int(client.mBytesPerFrame)
        let total = request.frameCount
        var framesWritten: Int64 = 0
        var scratch = [Float](repeating: 0, count: Self.bufferFrames * channels)

        try scratch.withUnsafeMutableBufferPointer { buffer in
            let base = UnsafeMutableRawPointer(buffer.baseAddress!)
            while framesWritten < total {
                if isCancelled { throw Failure.cancelled }
                let want = UInt32(min(Int64(Self.bufferFrames), total - framesWritten))
                var frames = want
                var list = AudioBufferList()
                list.mNumberBuffers = 1
                list.mBuffers.mNumberChannels = UInt32(channels)
                list.mBuffers.mDataByteSize = want * UInt32(bytesPerFrame)
                list.mBuffers.mData = base
                try check(ExtAudioFileRead(sourceRef, &frames, &list), "reading the Recording")
                guard frames > 0 else { break }   // master ran out early — write what we have

                applyGain(buffer, sampleCount: Int(frames) * channels)

                list.mBuffers.mDataByteSize = frames * UInt32(bytesPerFrame)
                try check(ExtAudioFileWrite(destRef, frames, &list), "writing the export")
                framesWritten += Int64(frames)
                onProgress(encodeStart + encodeSpan * Double(framesWritten) / Double(total))
            }
        }
    }

    /// The Export/Loudness seam (ADR-0013). Multiplies every sample by the one linear `scale` that
    /// folds the clamped Loudness correction and the manual Gain — **a single scalar multiply, never
    /// a limiter or a per-sample clamp** — so the two gains compose without double-normalizing and
    /// the whole path stays the pure multiply ADR-0013's no-double-normalize stance leans on. The
    /// scalar is exactly 1 for a faithful export (no normalization, 0 dB Gain), and the loop is
    /// skipped entirely then. The correction can never breach full scale (its ceiling is −3 dBTP);
    /// only an uncapped positive Gain can, and there the framework's float→int conversion saturates
    /// on the way to ALAC/AAC rather than wrapping — so no nonlinearity is inserted here. The `× 1.02`
    /// size estimate never moves with any of this (ADR-0012).
    private func applyGain(_ buffer: UnsafeMutableBufferPointer<Float>, sampleCount: Int) {
        guard scale != 1 else { return }   // faithful passthrough
        let s = scale
        for i in 0..<sampleCount { buffer[i] *= s }
    }

    /// Sets the lossy target bitrate on the underlying `AudioConverter` and asks for constrained
    /// VBR, then resyncs the file's data format per the `ExtAudioFile` contract (a NULL config).
    /// Best-effort: an encoder that refuses a quality knob still produces a valid file at its
    /// default, so a failure here is swallowed rather than aborting the export. ALAC has no target
    /// and is left alone.
    private func configureEncoder(_ destRef: ExtAudioFileRef, preset: QualityPreset) {
        guard let bitrate = preset.targetBitrate else { return }
        var converter: AudioConverterRef?
        var size = UInt32(MemoryLayout<AudioConverterRef?>.size)
        guard ExtAudioFileGetProperty(destRef, kExtAudioFileProperty_AudioConverter, &size, &converter) == noErr,
              let converter else { return }

        var mode = UInt32(kAudioCodecBitRateControlMode_VariableConstrained)
        _ = AudioConverterSetProperty(converter, kAudioCodecPropertyBitRateControlMode,
                                      UInt32(MemoryLayout<UInt32>.size), &mode)
        var rate = UInt32(bitrate)
        _ = AudioConverterSetProperty(converter, kAudioConverterEncodeBitRate,
                                      UInt32(MemoryLayout<UInt32>.size), &rate)

        // A NULL config resynchronises the file's data format with the reconfigured converter
        // (ExtAudioFile contract). Pass it as a null pointer-sized word rather than `&someCFArray?`,
        // which would form a raw pointer to a managed reference.
        var nullConfig: UnsafeRawPointer? = nil
        withUnsafePointer(to: &nullConfig) { pointer in
            _ = ExtAudioFileSetProperty(destRef, kExtAudioFileProperty_ConverterConfig,
                                        UInt32(MemoryLayout<UnsafeRawPointer?>.size), pointer)
        }
    }

    private func check(_ status: OSStatus, _ stage: String) throws {
        guard status == noErr else { throw Failure.coreAudio(stage: stage, status: status) }
    }
}
