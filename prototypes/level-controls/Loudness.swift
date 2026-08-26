//  PROTOTYPE — throwaway. The hand-rolled BS.1770-5 / EBU R128 measurement and the
//  ADR-0013 correction it drives. This is the real thing #24 settled, implemented just
//  faithfully enough that the previewed dB figure and the audition are honest — so the
//  cap / ceiling / undefined cases below are reached by real audio, not by a stub.
//
//  ADR-0013: target −16 LUFS integrated, ceiling −3 dBTP true peak, amplify capped at
//  +12 dB, attenuate uncapped, clamp (a pure scalar multiply) not a limiter.
//
//  The one shortcut, stated honestly: the K-weighting coefficients are the standard
//  BS.1770 pair for **48 kHz only**. Every fixture here is 48 kHz (ADR-0003's capture
//  rate), so it holds; a shipping build recomputes them per rate.

import AVFoundation

// MARK: - The correction contract (ADR-0013)

struct LoudnessContract {
    var targetLUFS = -16.0
    var ceilingDBTP = -3.0
    var amplifyCapDB = 12.0
    static let shared = LoudnessContract()
}

/// What the correction landed on, and why — the three short-fall cases each carry a caption.
struct Correction: Equatable {
    enum Outcome: Equatable {
        case full                 // hit the target
        case capped               // +12 dB cap stopped it short — guards the noise floor
        case ceiling              // −3 dBTP ceiling stopped it short — guards clipping
        case undefined            // nothing measurable — 0 dB, Export still completes
    }
    var gainDB: Double
    var outcome: Outcome
    var integratedLUFS: Double?   // nil when undefined
    var truePeakDBTP: Double?

    /// The applied figure, a decibel number, never LUFS (ADR-0013).
    var figure: String {
        outcome == .undefined ? "—" : String(format: "%+.1f dB", gainDB)
    }
    /// The plain-language caption, present only when the correction falls short.
    var caption: String? {
        switch outcome {
        case .full:      return nil
        case .capped:    return "limited to keep the noise floor down"
        case .ceiling:   return "peak ceiling reached"
        case .undefined: return "range too quiet to measure"
        }
    }
    var isShort: Bool { outcome != .full }
}

// MARK: - Cached, gated measurement

/// One BS.1770 gating block: 400 ms of audio, hopped every 100 ms (75 % overlap).
/// `z` is the channel-summed K-weighted mean square; `peak` is the block's 4×-oversampled
/// true peak (linear). Caching these is ADR-0013's "implementation refinement": the whole
/// file is K-filtered **once**, and a new Trim then re-runs only the gating arithmetic over
/// the blocks inside its range — which is what makes the previewed figure cheap to update
/// live as a handle moves.
private struct Block: Sendable {
    var midTime: Double
    var z: Double
    var peak: Float
}

/// Built once per Recording off a background thread; measured synchronously thereafter.
struct LoudnessAnalyzer: Sendable {
    private let blocks: [Block]
    let blockSeconds = 0.4

    /// Integrated loudness + true peak over a sub-range, from cached blocks only.
    /// A block counts if its **centre** lies inside the range — so a moved Trim just shifts
    /// which cached blocks are summed.
    func measure(range: ClosedRange<Double>) -> (integrated: Double?, truePeakDBTP: Double?) {
        let inside = blocks.filter { range.contains($0.midTime) }
        guard !inside.isEmpty else { return (nil, nil) }

        // 4×-oversampled true peak over the range.
        let peakLinear = inside.reduce(Float(0)) { Swift.max($0, $1.peak) }
        let truePeak = peakLinear > 0 ? 20 * log10(Double(peakLinear)) : -Double.infinity

        // Absolute gate at −70 LKFS.
        let absGated = inside.filter { loudness($0.z) >= -70 }
        guard !absGated.isEmpty else { return (nil, truePeak.isFinite ? truePeak : nil) }

        // Relative gate at (mean loudness of abs-gated blocks) − 10 LU.
        let meanZAbs = absGated.reduce(0) { $0 + $1.z } / Double(absGated.count)
        let relativeGate = loudness(meanZAbs) - 10
        let gated = absGated.filter { loudness($0.z) >= relativeGate }
        guard !gated.isEmpty else { return (nil, truePeak.isFinite ? truePeak : nil) }

        let meanZ = gated.reduce(0) { $0 + $1.z } / Double(gated.count)
        return (loudness(meanZ), truePeak.isFinite ? truePeak : nil)
    }

    /// The ADR-0013 correction over a range: desired gain toward the target, then the +12 dB
    /// cap on amplification and the −3 dBTP ceiling, whichever binds first. A pure scalar.
    func correction(range: ClosedRange<Double>, _ c: LoudnessContract = .shared) -> Correction {
        let (integrated, truePeak) = measure(range: range)
        guard let integrated, integrated.isFinite else {
            return Correction(gainDB: 0, outcome: .undefined,
                              integratedLUFS: nil, truePeakDBTP: truePeak)
        }
        let desired = c.targetLUFS - integrated              // + amplify, − attenuate

        // Amplification is capped; attenuation is not.
        let capped = min(desired, c.amplifyCapDB)
        // The ceiling caps how far we can push before true peak hits −3 dBTP. Only ever an
        // upper bound: attenuation lowers the peak, so it never binds going down.
        let ceilingLimit = (truePeak != nil) ? (c.ceilingDBTP - truePeak!) : .infinity
        let final = min(capped, ceilingLimit)

        let eps = 0.05
        let outcome: Correction.Outcome
        if abs(final - desired) < eps {
            outcome = .full
        } else if final <= ceilingLimit + eps && ceilingLimit < capped - eps {
            outcome = .ceiling                                // ceiling bound it before the cap
        } else {
            outcome = .capped                                 // the +12 cap bound it
        }
        return Correction(gainDB: final, outcome: outcome,
                          integratedLUFS: integrated, truePeakDBTP: truePeak)
    }

    private func loudness(_ z: Double) -> Double {
        z > 0 ? -0.691 + 10 * log10(z) : -Double.infinity
    }

    // MARK: Building (the once-per-file cost)

    /// Reads the whole master, K-filters both channels, and blocks it. Kept off the main
    /// thread; single-digit CPU-seconds per hour of 48 kHz per ADR-0013's research (#23).
    static func build(url: URL) -> LoudnessAnalyzer? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let rate = file.processingFormat.sampleRate
        let frames = AVAudioFrameCount(file.length)
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames),
              (try? file.read(into: buffer, frameCount: frames)) != nil,
              let channelData = buffer.floatChannelData
        else { return nil }

        let n = Int(buffer.frameLength)
        let channelCount = Int(file.processingFormat.channelCount)

        // K-weight each channel across the whole file, once.
        var weighted: [[Double]] = []
        for c in 0..<channelCount {
            weighted.append(KWeighting.filter(channelData[c], count: n))
        }

        let hop = Int(0.1 * rate)             // 100 ms
        let win = Int(0.4 * rate)             // 400 ms
        guard win > 0 else { return nil }

        var blocks: [Block] = []
        var start = 0
        let peaker = TruePeak()
        while start + win <= n {
            var z = 0.0
            for c in 0..<channelCount {
                var sq = 0.0
                let ch = weighted[c]
                for i in start..<(start + win) { sq += ch[i] * ch[i] }
                z += sq / Double(win)          // channel weight G = 1.0 for L and R
            }
            // True peak of this block, from the raw (un-weighted) samples, 4× oversampled.
            var peak: Float = 0
            for c in 0..<channelCount {
                peak = Swift.max(peak, peaker.blockPeak(channelData[c], from: start, count: win, limit: n))
            }
            blocks.append(Block(midTime: Double(start + win / 2) / rate, z: z, peak: peak))
            start += hop
        }
        Diag.note("loudness built \(url.lastPathComponent): \(blocks.count) blocks")
        return LoudnessAnalyzer(blocks: blocks)
    }
}

// MARK: - K-weighting (BS.1770-5 Annex 1, 48 kHz coefficients)

private enum KWeighting {
    // Stage 1: pre-filter (head/shelf). Stage 2: RLB high-pass.
    private static let s1 = Biquad(b0: 1.53512485958697, b1: -2.69169618940638, b2: 1.19839281085285,
                                   a1: -1.69065929318241, a2: 0.73248077421585)
    private static let s2 = Biquad(b0: 1.0, b1: -2.0, b2: 1.0,
                                   a1: -1.99004745483398, a2: 0.99007225036621)

    static func filter(_ x: UnsafePointer<Float>, count: Int) -> [Double] {
        var out = [Double](repeating: 0, count: count)
        var f1 = s1, f2 = s2
        for i in 0..<count { out[i] = f2.step(f1.step(Double(x[i]))) }
        return out
    }
}

private struct Biquad {
    let b0, b1, b2, a1, a2: Double
    var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
    mutating func step(_ x: Double) -> Double {
        let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1; x1 = x; y2 = y1; y1 = y
        return y
    }
}

// MARK: - True peak (4× oversampling, BS.1770-5 Annex 2)

/// A compact 4× oversampler: one polyphase windowed-sinc bank, 12 taps per phase. Enough to
/// surface inter-sample peaks that exceed every stored sample value — the whole reason
/// ADR-0013 and the research (#23) insist on true peak over sample peak.
private struct TruePeak {
    private let phases: [[Float]]
    private let tapsPerPhase = 12
    private let factor = 4

    init() {
        var banks: [[Float]] = []
        let taps = tapsPerPhase * factor
        let mid = Double(taps - 1) / 2
        for phase in 0..<factor {
            var coeffs = [Float](repeating: 0, count: tapsPerPhase)
            for t in 0..<tapsPerPhase {
                let idx = Double(t * factor + phase)
                let x = idx - mid
                let sinc = x == 0 ? 1.0 : sin(.pi * x / Double(factor)) / (.pi * x / Double(factor))
                // Blackman window over the full kernel.
                let w = 0.42 - 0.5 * cos(2 * .pi * idx / Double(taps - 1))
                       + 0.08 * cos(4 * .pi * idx / Double(taps - 1))
                coeffs[t] = Float(sinc * w)
            }
            banks.append(coeffs)
        }
        phases = banks
    }

    /// Max |sample| over the 4×-oversampled block. Reads a little past the block edges when
    /// it can; clamps at the file bounds otherwise.
    func blockPeak(_ x: UnsafePointer<Float>, from: Int, count: Int, limit: Int) -> Float {
        var peak: Float = 0
        let half = tapsPerPhase / 2
        for i in from..<(from + count) {
            for phase in phases {
                var acc: Float = 0
                for t in 0..<tapsPerPhase {
                    let s = i + t - half
                    acc += phase[t] * (s >= 0 && s < limit ? x[s] : 0)
                }
                peak = Swift.max(peak, abs(acc))
            }
        }
        return peak
    }
}
