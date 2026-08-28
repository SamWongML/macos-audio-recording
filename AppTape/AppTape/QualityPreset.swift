//
//  QualityPreset.swift
//  AppTape
//

import AudioToolbox
import CoreAudioTypes
import Foundation

/// The source's own format, as far as Export cares: rate, channel count, and the bit depth of
/// one sample. Read off the master (or an adopted file) — **never** assumed to be 48 kHz stereo,
/// because ADR-0006 adopts hand-placed files and the tap's own rate is whatever the Source ran at.
/// Export resamples nothing and downmixes nothing, so this format is also the *output's* rate and
/// channel count; the preset only chooses the codec and the bitrate.
struct SourceFormat: Equatable {
    var sampleRate: Double
    var channelCount: Int
    /// Bits in one channel of one source sample. The captured master is Float32 (32), so
    /// Master quality's estimate lands on ADR-0005's measured 46%-of-master figure; an adopted
    /// 16- or 24-bit file scales from its own depth.
    var bitsPerChannel: Int
}

/// A **Quality Preset** (CONTEXT.md): a named audio-quality setting offered at Export, whose
/// quality is what determines the exported file's size. There are exactly four, all producing
/// `.m4a` at the master's native rate and channel count with **no resampler and no downmix**
/// (ADR-0005, ADR-0012) — the preset chooses codec and bitrate and nothing else. VBR-constrained
/// where the codec is lossy.
///
/// The rung names are deliberate: the top rung is **Master quality**, 24-bit ALAC, and is *not*
/// called Lossless, because on macOS there is no lossless path from the Float32 master and the
/// word would be a claim the file does not honour (ADR-0005).
enum QualityPreset: String, CaseIterable, Identifiable, Sendable {
    case master
    case high
    case standard
    case compact

    var id: String { rawValue }

    /// AAC 256 is the default (issue #9): transparent for consumer audio and a quarter of the
    /// master's cost.
    static let defaultPreset: QualityPreset = .high

    /// The rung's name, as it appears in the picker.
    var displayName: String {
        switch self {
        case .master: return "Master quality"
        case .high: return "High"
        case .standard: return "Standard"
        case .compact: return "Compact"
        }
    }

    /// The codec and bitrate, in words — the static half of the non-editable subtitle. The rate
    /// and channel count come from the source (`subtitle(for:)`).
    var codecLabel: String {
        switch self {
        case .master: return "24-bit ALAC"
        case .high: return "AAC 256 kbps"
        case .standard: return "AAC 128 kbps"
        case .compact: return "HE-AAC 64 kbps"
        }
    }

    /// The full non-editable subtitle: codec/bitrate plus the source's rate and channels, which
    /// Export carries through untouched. Shown under the picker so the parameters are always
    /// visible and never editable (issue #9).
    func subtitle(for format: SourceFormat) -> String {
        "\(codecLabel) · \(Self.rateText(format.sampleRate)) \(Self.channelText(format.channelCount))"
    }

    /// The lossy target bitrate the AAC family encodes to, or nil for the lossless ALAC rung
    /// (whose size is a property of the content, not a target).
    var targetBitrate: Int? {
        switch self {
        case .master: return nil
        case .high: return 256_000
        case .standard: return 128_000
        case .compact: return 64_000
        }
    }

    /// The effective bits-per-second used for the size estimate. Lossy rungs are their target
    /// bitrate, flat across sample rates as a constant-bitrate target is. The ALAC rung has no
    /// target, so it is estimated as **46% of the source's uncompressed rate** — ADR-0005's
    /// measured figure (633 MB/hour at 48 kHz stereo Float32), scaled by the source's real rate,
    /// channels and depth so a 96 kHz or 24-bit source estimates from its own footprint.
    func estimatedBitsPerSecond(for format: SourceFormat) -> Double {
        if let targetBitrate { return Double(targetBitrate) }
        let uncompressed = format.sampleRate * Double(format.channelCount) * Double(format.bitsPerChannel)
        return uncompressed * Self.alacFraction
    }

    /// ALAC's measured share of the Float32 master (ADR-0005: 46%). The number a size or
    /// duration policy should use for the Master-quality rung.
    static let alacFraction = 0.46

    // MARK: - The encode format

    /// The compressed file-data format this preset writes: an ASBD carrying only the codec,
    /// rate and channel count. The encoder fills in the packetisation. ALAC additionally stamps
    /// its source-bit-depth flag as 24-bit (ADR-0005) — the eight bits below the master's float
    /// are inaudible against post-mix consumer audio and this is where they are dropped.
    func fileFormat(for format: SourceFormat) -> AudioStreamBasicDescription {
        var asbd = AudioStreamBasicDescription()
        asbd.mSampleRate = format.sampleRate
        asbd.mChannelsPerFrame = UInt32(format.channelCount)
        switch self {
        case .master:
            asbd.mFormatID = kAudioFormatAppleLossless
            asbd.mFormatFlags = kAppleLosslessFormatFlag_24BitSourceData
        case .high, .standard:
            asbd.mFormatID = kAudioFormatMPEG4AAC
        case .compact:
            asbd.mFormatID = kAudioFormatMPEG4AAC_HE
        }
        return asbd
    }

    // MARK: - Subtitle helpers

    /// `48 kHz`, `44.1 kHz` — trailing `.0` dropped so whole-kHz rates read cleanly.
    static func rateText(_ sampleRate: Double) -> String {
        let khz = sampleRate / 1000
        let rounded = (khz * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return "\(Int(rounded)) kHz"
        }
        return "\(rounded) kHz"
    }

    static func channelText(_ channelCount: Int) -> String {
        switch channelCount {
        case 1: return "mono"
        case 2: return "stereo"
        default: return "\(channelCount) ch"
        }
    }
}

extension AudioStreamBasicDescription {
    /// Interleaved, packed Float32 at a given rate and channel count — the client format the whole
    /// Export path speaks (ADR-0012): the encode reads and writes it, and the Loudness measurement
    /// reads it, always at the source's own rate and channels so nothing is resampled or downmixed.
    static func interleavedFloat(rate: Double, channels: Int) -> AudioStreamBasicDescription {
        let bytesPerFrame = UInt32(channels * MemoryLayout<Float>.size)
        return AudioStreamBasicDescription(
            mSampleRate: rate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: bytesPerFrame, mFramesPerPacket: 1, mBytesPerFrame: bytesPerFrame,
            mChannelsPerFrame: UInt32(channels), mBitsPerChannel: 32, mReserved: 0)
    }
}
