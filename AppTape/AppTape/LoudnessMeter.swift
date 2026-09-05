//
//  LoudnessMeter.swift
//  AppTape
//

import AudioToolbox
import Foundation

/// A **hand-rolled ITU-R BS.1770-5 / EBU R128 pass** over a trimmed range of Float32 frames
/// (ADR-0013). It is deliberately *not* `MusicUnderstanding.LoudnessResult`: that type applies no
/// gain and takes no time-range, so it cannot measure a Trim or drive the correction. This one is
/// fully specified by BS.1770-5 Annexes 1–2 and small — K-weighting, 400 ms gated blocks, and a 4×
/// oversampled true peak — run over the same trimmed Float32 the encode already reads.
///
/// `LoudnessAnalyzer` is the streaming core: push interleaved Float32 chunks and call `finish()`, so
/// the file path never holds an hour of audio in memory and a test can push one buffer. `LoudnessMeter`
/// is the file entry point Export and the inspector preview share.
///
/// **Everything in this file is `nonisolated`, and that is load-bearing** (ADR-0022). The target sets
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so an unannotated type here would be main-actor
/// isolated — and a `Task.detached` that calls into it would hop straight back to the main thread and
/// hold it for the whole BS.1770 pass. This is the longest-running pure computation in the app; it
/// must never be reachable on the main actor.
nonisolated enum LoudnessMeter {
    /// Reads the master's trimmed range as interleaved Float32 (the encode's own client format) and
    /// measures it. `onProgress` reports `0...1` across the read, so a normalized Export can show one
    /// continuous measure-then-encode bar. Throws on a Core Audio failure; a genuinely unmeasurable
    /// range is not an error — it returns a measurement whose `integratedLUFS` is `nil`.
    /// `isCancelled`, polled each read chunk, lets a superseded preview pass (a dragging Trim handle,
    /// a flipped toggle) stop its filtering early instead of running the whole range to completion;
    /// the caller discards the partial result. The Export path leaves it at the default and always
    /// runs to the end.
    static func measure(url: URL, startFrame: Int64, frameCount: Int64,
                        isCancelled: () -> Bool = { false },
                        onProgress: (Double) -> Void = { _ in }) throws -> LoudnessMeasurement {
        guard frameCount > 0 else {
            return LoudnessMeasurement(integratedLUFS: nil, truePeakDBTP: -.infinity)
        }

        var sourceRef: ExtAudioFileRef?
        try check(ExtAudioFileOpenURL(url as CFURL, &sourceRef), "opening the Recording")
        guard let sourceRef else { throw Failure.coreAudio(stage: "opening the Recording", status: -1) }
        defer { ExtAudioFileDispose(sourceRef) }

        var format = AudioStreamBasicDescription()
        var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try check(ExtAudioFileGetProperty(sourceRef, kExtAudioFileProperty_FileDataFormat,
                                          &formatSize, &format), "reading the Recording's format")
        let channels = max(1, Int(format.mChannelsPerFrame))
        let rate = format.mSampleRate
        guard rate > 0 else {
            return LoudnessMeasurement(integratedLUFS: nil, truePeakDBTP: -.infinity)
        }

        var client = AudioStreamBasicDescription.interleavedFloat(rate: rate, channels: channels)
        let clientSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try check(ExtAudioFileSetProperty(sourceRef, kExtAudioFileProperty_ClientDataFormat,
                                          clientSize, &client), "preparing to read")
        try check(ExtAudioFileSeek(sourceRef, startFrame), "seeking to the Trim")

        let analyzer = LoudnessAnalyzer(sampleRate: rate, channels: channels)
        let chunkFrames = 65_536
        var scratch = [Float](repeating: 0, count: chunkFrames * channels)
        var framesRead: Int64 = 0

        try scratch.withUnsafeMutableBufferPointer { buffer in
            let base = UnsafeMutableRawPointer(buffer.baseAddress!)
            while framesRead < frameCount {
                if isCancelled() { break }   // superseded preview — stop early, result is discarded
                let want = UInt32(min(Int64(chunkFrames), frameCount - framesRead))
                var frames = want
                var list = AudioBufferList()
                list.mNumberBuffers = 1
                list.mBuffers.mNumberChannels = UInt32(channels)
                list.mBuffers.mDataByteSize = want * client.mBytesPerFrame
                list.mBuffers.mData = base
                try check(ExtAudioFileRead(sourceRef, &frames, &list), "reading the Recording")
                guard frames > 0 else { break }   // master ran out early
                analyzer.process(buffer.baseAddress!, frameCount: Int(frames))
                framesRead += Int64(frames)
                onProgress(Double(framesRead) / Double(frameCount))
            }
        }
        return analyzer.finish()
    }

    enum Failure: Error, CustomStringConvertible {
        case coreAudio(stage: String, status: OSStatus)
        var description: String {
            switch self {
            case .coreAudio(let stage, let status): return "Loudness measurement failed while \(stage) (error \(status))."
            }
        }
    }

    private static func check(_ status: OSStatus, _ stage: String) throws {
        guard status == noErr else { throw Failure.coreAudio(stage: stage, status: status) }
    }
}

/// The streaming BS.1770-5 measurement (ADR-0013). Two things run in parallel over the frames:
///
/// - **Loudness.** Each channel is K-weighted (a rate-adaptive shelf + high-pass cascade, Annex 1),
///   then squared and accumulated into 100 ms sub-blocks. Four consecutive sub-blocks form one
///   400 ms gating block stepped every 100 ms (75 % overlap). At `finish()` the blocks are gated —
///   absolute at −70 LKFS, then relative at −10 LU below the gated mean — and the surviving blocks'
///   mean power becomes the integrated loudness.
/// - **True peak.** The *raw* (un-weighted) signal is 4× oversampled through the BS.1770-4 Annex 2
///   polyphase FIR; the largest interpolated magnitude is the dBTP the ceiling clamps against.
///
/// A range with no block that clears the absolute gate — silence, or a Trim shorter than one 400 ms
/// block — has no integrated loudness, reported as `nil`.
///
/// `nonisolated` for the reason in `LoudnessMeter`'s note: this is the loop that would otherwise
/// hold the main thread (ADR-0022).
nonisolated final class LoudnessAnalyzer {
    private let channels: Int
    private let weights: [Double]

    // K-weighting: two biquads (pre-shelf, then RLB high-pass) per channel, Direct Form II Transposed.
    private let shelf: Biquad
    private let highpass: Biquad
    private var shelfState: [BiquadState]
    private var rlbState: [BiquadState]

    // Gating blocks.
    private let subBlockFrames: Int          // 100 ms
    private let blockFrames: Double          // 400 ms, for the mean-square denominator
    private var subSumSquares: [Double]      // per-channel running sum over the current sub-block
    private var subFrameCount = 0
    private var recentSubBlocks: [[Double]] = []   // last up to 4 completed sub-blocks (per channel)
    private var blockPowers: [Double] = []         // channel-weighted mean square, one per 400 ms block

    // True peak: a 12-tap window per channel feeding the 4-phase interpolation FIR.
    private var peakWindow: [Float]          // channels × 12, most-recent-last ring per channel
    private var peakPos = 0
    private var maxPeak: Float = 0

    init(sampleRate: Double, channels: Int) {
        self.channels = channels
        self.weights = Self.channelWeights(channels)
        self.shelf = Biquad.kWeightingShelf(sampleRate: sampleRate)
        self.highpass = Biquad.kWeightingHighpass(sampleRate: sampleRate)
        self.shelfState = Array(repeating: BiquadState(), count: channels)
        self.rlbState = Array(repeating: BiquadState(), count: channels)
        self.subBlockFrames = max(1, Int((sampleRate * 0.1).rounded()))
        self.blockFrames = Double(subBlockFrames * 4)
        self.subSumSquares = Array(repeating: 0, count: channels)
        self.peakWindow = Array(repeating: 0, count: channels * Self.peakTaps)
    }

    /// Feeds `frameCount` interleaved frames. Cheap enough to call per read chunk.
    func process(_ samples: UnsafePointer<Float>, frameCount: Int) {
        for frame in 0..<frameCount {
            let offset = frame * channels
            for channel in 0..<channels {
                let x = samples[offset + channel]
                // K-weighting for loudness.
                let y1 = shelf.process(Double(x), state: &shelfState[channel])
                let y2 = highpass.process(y1, state: &rlbState[channel])
                subSumSquares[channel] += y2 * y2
                // True peak on the raw sample.
                accumulatePeak(x, channel: channel)
            }
            subFrameCount += 1
            if subFrameCount == subBlockFrames { closeSubBlock() }
        }
    }

    /// Gates the blocks and forms the integrated loudness (ADR-0013). `nil` when unmeasurable.
    func finish() -> LoudnessMeasurement {
        let truePeak = maxPeak > 0 ? 20 * log10(Double(maxPeak)) : -.infinity
        guard !blockPowers.isEmpty else {
            return LoudnessMeasurement(integratedLUFS: nil, truePeakDBTP: truePeak)
        }

        // Absolute gate at −70 LKFS. Block loudness = −0.691 + 10·log10(power).
        let absoluteThreshold = pow(10.0, (-70.0 + 0.691) / 10.0)
        let absoluteKept = blockPowers.filter { $0 >= absoluteThreshold }
        guard !absoluteKept.isEmpty else {
            return LoudnessMeasurement(integratedLUFS: nil, truePeakDBTP: truePeak)
        }

        // Relative gate at −10 LU below the gated mean loudness.
        let gatedMean = absoluteKept.reduce(0, +) / Double(absoluteKept.count)
        let relativeThresholdLoudness = -0.691 + 10 * log10(gatedMean) - 10
        let relativeThreshold = pow(10.0, (relativeThresholdLoudness + 0.691) / 10.0)
        let kept = absoluteKept.filter { $0 >= relativeThreshold }
        guard !kept.isEmpty else {
            return LoudnessMeasurement(integratedLUFS: nil, truePeakDBTP: truePeak)
        }

        let mean = kept.reduce(0, +) / Double(kept.count)
        let integrated = -0.691 + 10 * log10(mean)
        return LoudnessMeasurement(integratedLUFS: integrated, truePeakDBTP: truePeak)
    }

    // MARK: - Gating blocks

    private func closeSubBlock() {
        recentSubBlocks.append(subSumSquares)
        if recentSubBlocks.count > 4 { recentSubBlocks.removeFirst() }
        if recentSubBlocks.count == 4 {
            var power = 0.0
            for channel in 0..<channels {
                let sum = recentSubBlocks.reduce(0.0) { $0 + $1[channel] }
                let meanSquare = sum / blockFrames
                power += weights[channel] * meanSquare
            }
            blockPowers.append(power)
        }
        subSumSquares = Array(repeating: 0, count: channels)
        subFrameCount = 0
    }

    // MARK: - True peak (BS.1770-4 Annex 2, 4× oversampling)

    private static let peakTaps = 12

    private func accumulatePeak(_ sample: Float, channel: Int) {
        // Store the new sample, then convolve the 12-tap window with each of the 4 phases.
        let windowBase = channel * Self.peakTaps
        peakWindow[windowBase + peakPos] = sample
        // Advance this channel's ring on the last channel of the frame (all channels share peakPos).
        // The window is read most-recent-first: index (peakPos - k) mod 12.
        for phase in 0..<4 {
            var acc: Float = 0
            let coeffs = Self.peakCoefficients[phase]
            for k in 0..<Self.peakTaps {
                let idx = (peakPos - k + Self.peakTaps) % Self.peakTaps
                acc += coeffs[k] * peakWindow[windowBase + idx]
            }
            let magnitude = abs(acc)
            if magnitude > maxPeak { maxPeak = magnitude }
        }
        if channel == channels - 1 {
            peakPos = (peakPos + 1) % Self.peakTaps
        }
    }

    /// BS.1770-4 Annex 2, Table 3: the 4× oversampling interpolation filter, 12 taps per phase.
    /// Phase 3 is phase 0 reversed and phase 2 is phase 1 reversed — the filter is linear phase.
    private static let peakCoefficients: [[Float]] = [
        [0.0017089843750, 0.0109863281250, -0.0196533203125, 0.0332031250000,
         -0.0594482421875, 0.1373291015625, 0.9721679687500, -0.1022949218750,
         0.0476074218750, -0.0266113281250, 0.0148925781250, -0.0083007812500],
        [-0.0291748046875, 0.0292968750000, -0.0517578125000, 0.0891113281250,
         -0.1665039062500, 0.4650878906250, 0.7797851562500, -0.2003173828125,
         0.1015625000000, -0.0582275390625, 0.0330810546875, -0.0189208984375],
        [-0.0189208984375, 0.0330810546875, -0.0582275390625, 0.1015625000000,
         -0.2003173828125, 0.7797851562500, 0.4650878906250, -0.1665039062500,
         0.0891113281250, -0.0517578125000, 0.0292968750000, -0.0291748046875],
        [-0.0083007812500, 0.0148925781250, -0.0266113281250, 0.0476074218750,
         -0.1022949218750, 0.9721679687500, 0.1373291015625, -0.0594482421875,
         0.0332031250000, -0.0196533203125, 0.0109863281250, 0.0017089843750],
    ]

    // MARK: - Channel weights (Gc)

    /// BS.1770 channel weights. Mono and stereo weight every channel 1.0; a 5.1 layout excludes LFE
    /// and weights the two surrounds ~+1.5 dB. Captured audio is almost always mono or stereo.
    private static func channelWeights(_ channels: Int) -> [Double] {
        guard channels >= 6 else { return Array(repeating: 1.0, count: channels) }
        var w = Array(repeating: 1.0, count: channels)   // L R C … in a standard 5.1 order
        w[3] = 0.0                                        // LFE excluded
        w[4] = 1.41; w[5] = 1.41                          // Ls, Rs
        return w
    }
}

// MARK: - Biquad

/// One second-order section, Direct Form II Transposed. Coefficients are normalised so `a0 == 1`.
/// `nonisolated`, like everything else the BS.1770 pass touches (ADR-0022) — a main-actor biquad
/// would drag the whole filter cascade back onto the main thread one sample at a time.
nonisolated struct Biquad {
    let b0, b1, b2, a1, a2: Double

    @inline(__always)
    func process(_ x: Double, state: inout BiquadState) -> Double {
        let y = b0 * x + state.z1
        state.z1 = b1 * x - a1 * y + state.z2
        state.z2 = b2 * x - a2 * y
        return y
    }

    /// The K-weighting **pre-filter** (Annex 1 stage 1): a high-frequency shelf. Coefficients are
    /// derived from the analog prototype at the actual sample rate (the bilinear transform in
    /// libebur128's derivation), so a 44.1, 48 or 96 kHz capture is weighted correctly rather than
    /// with the 48 kHz table forced onto every rate.
    static func kWeightingShelf(sampleRate: Double) -> Biquad {
        let f0 = 1681.9744509555319
        let G = 3.99984385397
        let Q = 0.7071752369554196
        let K = tan(Double.pi * f0 / sampleRate)
        let Vh = pow(10.0, G / 20.0)
        let Vb = pow(Vh, 0.4996667741545416)
        let a0 = 1.0 + K / Q + K * K
        return Biquad(
            b0: (Vh + Vb * K / Q + K * K) / a0,
            b1: 2.0 * (K * K - Vh) / a0,
            b2: (Vh - Vb * K / Q + K * K) / a0,
            a1: 2.0 * (K * K - 1.0) / a0,
            a2: (1.0 - K / Q + K * K) / a0)
    }

    /// The K-weighting **RLB high-pass** (Annex 1 stage 2), likewise derived at the real rate.
    static func kWeightingHighpass(sampleRate: Double) -> Biquad {
        let f0 = 38.13547087613982
        let Q = 0.5003270373253953
        let K = tan(Double.pi * f0 / sampleRate)
        let a0 = 1.0 + K / Q + K * K
        return Biquad(
            b0: 1.0, b1: -2.0, b2: 1.0,
            a1: 2.0 * (K * K - 1.0) / a0,
            a2: (1.0 - K / Q + K * K) / a0)
    }
}

/// The two delay elements of one Direct Form II Transposed section.
nonisolated struct BiquadState { var z1 = 0.0; var z2 = 0.0 }
