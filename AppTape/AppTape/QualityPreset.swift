import AudioToolbox
import CoreAudioTypes
import Foundation

/// The source's own format, as far as Export cares: rate, channel count, and the bit depth of one
/// sample.
struct SourceFormat: Equatable {
    var sampleRate: Double
    var channelCount: Int
    /// Bits in one channel of one source sample.
    var bitsPerChannel: Int
}

/// A Quality Preset (CONTEXT.md): a named audio-quality setting offered at Export, whose
/// quality is what determines the exported file's size.
nonisolated enum QualityPreset: String, CaseIterable, Identifiable, Sendable {
    case master
    case high
    case standard
    case compact

    var id: String { rawValue }

    /// AAC 256 is the default: transparent for consumer audio and a quarter of the
    /// master's cost.
    static let defaultPreset: QualityPreset = .high

    /// The preset row's name, as it appears in the picker.
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
    /// Export carries through untouched.
    func subtitle(for format: SourceFormat) -> String {
        "\(codecLabel) · \(Self.rateText(format.sampleRate)) \(Self.channelText(format.channelCount))"
    }

    /// The lossy target bitrate the AAC family encodes to, or nil for the lossless ALAC preset row
    /// (whose size is a property of the content, not a target).
    var targetBitrate: Int? {
        switch self {
        case .master: return nil
        case .high: return 256_000
        case .standard: return 128_000
        case .compact: return 64_000
        }
    }

    /// The effective bits-per-second used for the size estimate.
    func estimatedBitsPerSecond(for format: SourceFormat) -> Double {
        if let targetBitrate { return Double(targetBitrate) }
        let uncompressed = format.sampleRate * Double(format.channelCount) * Double(format.bitsPerChannel)
        return uncompressed * Self.alacFraction
    }

    /// ALAC's measured share of the Float32 master (46%). The number a size or
    /// duration policy should use for the Master-quality preset row.
    static let alacFraction = 0.46

    // MARK: - The encode format

    /// The compressed file-data format this preset writes: an ASBD carrying only the codec, rate
    /// and channel count.
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

    // MARK: - Faithful-or-refuse

    /// Whether this preset can encode `format` faithfully — with no resample and no downmix.
    enum Encodability: Equatable {
        case available
        case unavailable(reason: String)

        var isAvailable: Bool { self == .available }
        var reason: String? { if case .unavailable(let reason) = self { return reason } else { return nil } }
    }

    /// AAC-LC and HE-AAC both cap at 48 kHz; ALAC takes any rate. Above this the three AAC preset rows
    /// refuse rather than let the framework silently resample.
    static let aacMaxSampleRate: Double = 48_000
    /// AAC-LC and ALAC both encode up to 8 channels (mono through 7.1). Beyond that even Master
    /// refuses — the one exotic case with no faithful preset row.
    static let maxChannels = 8

    func encodability(for format: SourceFormat) -> Encodability {
        // Each preset row's blocker is the first of its codec's limits the source trips; nil is a clean pass.
        let reason: String?
        switch self {
        case .master:
            reason = Self.channelCeilingReason(format, codec: "ALAC")
        case .high, .standard:
            reason = Self.aacRateReason(format, codec: "AAC")
                ?? Self.channelCeilingReason(format, codec: "AAC")
        case .compact:
            reason = Self.aacRateReason(format, codec: "HE-AAC")
                ?? Self.channelCeilingReason(format, codec: "HE-AAC")
                ?? Self.evenChannelReason(format)
        }
        return reason.map { .unavailable(reason: $0) } ?? .available
    }

    /// The AAC family caps at 48 kHz; ALAC is unbounded, so only the AAC preset rows ask this.
    private static func aacRateReason(_ format: SourceFormat, codec: String) -> String? {
        format.sampleRate > aacMaxSampleRate
            ? "\(codec) can't encode above 48 kHz — this file is \(rateText(format.sampleRate))."
            : nil
    }

    /// AAC-LC, HE-AAC and ALAC all encode up to 8 channels; beyond that there is no faithful preset row.
    private static func channelCeilingReason(_ format: SourceFormat, codec: String) -> String? {
        format.channelCount > maxChannels
            ? "\(codec) supports up to \(maxChannels) channels — this file has \(format.channelCount)."
            : nil
    }

    /// HE-AAC ("Compact") encodes even channel counts only, so mono and odd multichannel refuse it.
    private static func evenChannelReason(_ format: SourceFormat) -> String? {
        format.channelCount % 2 != 0
            ? "HE-AAC needs an even number of channels — this file \(channelPhrase(format.channelCount))."
            : nil
    }

    /// `is mono` / `is stereo` / `has 3 channels` — the tail of a blocker reason, so it reads as a
    /// sentence rather than a bare number.
    private static func channelPhrase(_ channels: Int) -> String {
        switch channels {
        case 1: return "is mono"
        case 2: return "is stereo"
        default: return "has \(channels) channels"
        }
    }

    /// The outcome of choosing a preset row in the Export picker for an adopted file.
    enum PresetPick: Equatable {
        /// Store `preset` as the new app-wide sticky preference, and drop any display-over.
        case setSticky(QualityPreset)
        /// Hold `preset` as this file's display-over; leave the sticky preference unchanged.
        case displayOver(QualityPreset)
        /// The chosen preset row can't encode this file: do nothing.
        case ignore

        static func resolve(picking preset: QualityPreset, sticky: QualityPreset,
                            format: SourceFormat) -> PresetPick {
            guard preset.encodability(for: format).isAvailable else { return .ignore }
            return sticky.encodability(for: format).isAvailable ? .setSticky(preset)
                                                                : .displayOver(preset)
        }
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
    /// Interleaved, packed Float32 at a given rate and channel count — the client format the
    /// whole Export path speaks: the encode reads and writes it, and the Loudness measurement reads
    /// it, always at the source's own rate and channels so nothing is resampled or downmixed.
    nonisolated static func interleavedFloat(rate: Double, channels: Int) -> AudioStreamBasicDescription {
        let bytesPerFrame = UInt32(channels * MemoryLayout<Float>.size)
        return AudioStreamBasicDescription(
            mSampleRate: rate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: bytesPerFrame, mFramesPerPacket: 1, mBytesPerFrame: bytesPerFrame,
            mChannelsPerFrame: UInt32(channels), mBitsPerChannel: 32, mReserved: 0)
    }
}
