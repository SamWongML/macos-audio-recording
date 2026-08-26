//  PROTOTYPE — throwaway. Synthesises short CAF masters (ADR-0003 format: Float32, stereo,
//  48 kHz; ADR-0006 naming) engineered so the ADR-0013 correction lands on each distinct
//  case, and so a moved Trim changes the reading:
//
//    Quiet talk   ~ −24 LUFS, clean         → full boost, e.g. +8 dB (no caption)
//    Phone call   ~ −33 LUFS, audible hiss  → +12 dB CAP  ("noise floor" caption)
//    Loud music   ~ −11 LUFS, peaks −5 dBTP → attenuate, full (no caption)
//    Peaky mix    ~ −19 LUFS, peaks ~0 dBTP → −3 dBTP CEILING (lands short)
//    Silent room  below the −70 gate         → UNDEFINED (0 dB, Export still completes)
//
//  Levels are tuned by ear-of-the-meter, not to the decibel — the point is that each case
//  is reliably reached. The coordinator logs the measured figure at load so they can be
//  nudged after a run (see /tmp/level-controls-prototype.log).

import AVFoundation

enum Fixtures {
    static let sampleRate = 48_000.0

    struct Spec {
        let source: String
        let seconds: Double
        let clock: String
        let shape: (Double) -> Float
    }

    static let specs: [Spec] = [
        Spec(source: "Quiet podcast", seconds: 30, clock: "09.14.02", shape: quietPodcast),
        Spec(source: "Phone call",    seconds: 24, clock: "10.02.10", shape: phoneCall),
        Spec(source: "Loud master",   seconds: 30, clock: "11.47.31", shape: loudMaster),
        Spec(source: "Peaky mix",     seconds: 24, clock: "13.20.55", shape: peakyMix),
        Spec(source: "Silent room",   seconds: 12, clock: "16.20.08", shape: silentRoom),
    ]

    // MARK: - Shapes. Each carries an internal contrast so trimming changes the measurement.

    /// Quiet but clean and low-crest (soft-compressed, so no wild transients) — the ordinary
    /// happy path: wants a healthy amplify and gets all of it. A louder phrase sits 12–20 s in,
    /// so trimming to it needs less boost than the quiet head — the live-update case.
    private static func quietPodcast(_ t: Double) -> Float {
        let level: Float = (12...20).contains(t) ? 1.15 : 0.7
        return compress(speech(t, level: 1.0), by: 5) * level
    }

    /// Very quiet speech over an audible hiss floor — the capture that wants more than +12 dB
    /// and gets it withheld, so the hiss is not lifted with it.
    private static func phoneCall(_ t: Double) -> Float {
        speech(t, level: 0.030) + hiss(t, level: 0.0065)
    }

    /// A hot, loud master: high level, peaks a few dB below full. Wants attenuation, which is
    /// uncapped and clean — the plain "−5.0 dB" full case.
    private static func loudMaster(_ t: Double) -> Float {
        let swell = 0.9 + 0.1 * Float(sin(2 * .pi * 0.08 * t))
        return chord(t, level: 0.92) * swell
    }

    /// Quiet body, violent transients that ride near full scale — a drum-forward mix. Loudness
    /// says "amplify", true peak says "not that far". The ceiling stops it short of −16.
    private static func peakyMix(_ t: Double) -> Float {
        let body = chord(t, level: 0.028)
        let beat = t.truncatingRemainder(dividingBy: 0.48)
        let hit = Float(exp(-beat * 40)) * 0.5 * Float(noise(t * 1.7))    // ~ −5 dBTP spikes
        return body + hit
    }

    /// Room tone only, safely below the −70 LKFS absolute gate — nothing to measure.
    private static func silentRoom(_ t: Double) -> Float {
        hiss(t, level: 0.00018)
    }

    // MARK: - Generators (from the editor-window prototype's Fixtures, level-parameterised)

    private static func speech(_ t: Double, level: Double) -> Float {
        let syllable = max(0, sin(2 * .pi * 3.7 * t))
        let phrase = max(0, sin(2 * .pi * 0.19 * t + 0.9))
        let breath = 0.5 + 0.5 * sin(2 * .pi * 0.043 * t)
        let carrier = 0.6 * noise(t) + 0.4 * sin(2 * .pi * (170 + 40 * sin(2 * .pi * 1.3 * t)) * t)
        return Float(level * breath * phrase * pow(syllable, 1.6) * carrier)
    }

    private static func chord(_ t: Double, level: Double) -> Float {
        let body = sin(2 * .pi * 110 * t) + 0.7 * sin(2 * .pi * 165 * t) + 0.5 * sin(2 * .pi * 220 * t)
        let swell = 0.75 + 0.25 * sin(2 * .pi * 0.11 * t)
        return Float(level * swell * body / 2.2)
    }

    private static func hiss(_ t: Double, level: Double) -> Float {
        Float(level * (noise(t) + 0.4 * sin(2 * .pi * 60 * t)))
    }

    /// Soft saturation — tames crest factor so a signal can be amplified toward the target
    /// without its peaks hitting the ceiling first.
    private static func compress(_ x: Float, by k: Float) -> Float { tanh(k * x) / k }

    /// Deterministic value noise — no RNG, so regenerating gives identical fixtures.
    private static func noise(_ t: Double) -> Double {
        let x = sin(t * 12_9898.0) * 43_758.5453
        return 2 * (x - x.rounded(.down)) - 1
    }

    // MARK: - Writing

    private static let today = DateComponents(calendar: .current, year: 2026, month: 8, day: 23,
                                              hour: 12).date!

    static func ensureLibrary() throws {
        let dir = Library.folder
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyy-MM-dd"

        for spec in specs {
            let url = dir.appending(path: "\(spec.source) \(stamp.string(from: today)) at \(spec.clock).caf")
            guard !FileManager.default.fileExists(atPath: url.path) else { continue }
            try Diag.time("fixture \(spec.source) \(Int(spec.seconds))s") { try write(spec, to: url) }
            let parts = spec.clock.split(separator: ".").compactMap { Int($0) }
            let recordedAt = Calendar.current.date(bySettingHour: parts[0], minute: parts[1],
                                                   second: parts[2], of: today)!
            try? FileManager.default.setAttributes([.modificationDate: recordedAt],
                                                   ofItemAtPath: url.path)
        }
    }

    private static func write(_ spec: Spec, to url: URL) throws {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                   sampleRate: sampleRate, channels: 2, interleaved: false)!
        let file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: true,
        ], commonFormat: .pcmFormatFloat32, interleaved: false)

        let chunk: AVAudioFrameCount = 48_000
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk)!
        let total = Int(spec.seconds * sampleRate)
        var written = 0
        while written < total {
            let n = min(Int(chunk), total - written)
            buffer.frameLength = AVAudioFrameCount(n)
            let left = buffer.floatChannelData![0], right = buffer.floatChannelData![1]
            for i in 0..<n {
                let t = Double(written + i) / sampleRate
                let s = spec.shape(t)
                left[i] = s
                right[i] = s * Float(0.82 + 0.18 * sin(2 * .pi * 0.07 * t))
            }
            try file.write(from: buffer)
            written += n
        }
    }
}
