//  PROTOTYPE — throwaway. Synthesises CAF masters so the editor has something real to draw.
//
//  Format matches ADR-0003: CAF, Float32 PCM, stereo, 48 kHz. Names match ADR-0006:
//  "<Source> YYYY-MM-DD at HH.mm.ss.caf", written into ~/Music/AppTape.
//
//  There is no capture here and no tap — this is a stand-in for Recordings that do not
//  exist yet on this machine. Delete them with the command in the README.

import AVFoundation

enum Fixtures {
    static let sampleRate = 48_000.0

    struct Spec {
        let source: String
        let seconds: Double
        let clock: String       // "HH.mm.ss", so Finder order is deterministic
        let shape: (Double, Double) -> Float   // (t, duration) -> sample
    }

    /// Deliberately awkward material: a long one that makes pixel density hurt, a flat one
    /// that tells you nothing about position, and a quiet head that begs to be trimmed off.
    static let specs: [Spec] = [
        Spec(source: "Safari", seconds: 20 * 60, clock: "09.14.02", shape: lecture),
        Spec(source: "Google Chrome", seconds: 3 * 60, clock: "11.47.31", shape: podcast),
        Spec(source: "Spotify", seconds: 90, clock: "14.02.55", shape: music),
        Spec(source: "QuickTime Player", seconds: 30, clock: "16.20.08", shape: tone),
    ]

    // MARK: - Shapes

    /// Twenty minutes of near-uniform speech. Four short pauses are the only landmarks,
    /// which is the point: at full width you cannot see where anything is.
    private static func lecture(_ t: Double, _ duration: Double) -> Float {
        let pauses: [ClosedRange<Double>] = [
            240...246, 512...519, 780...784.5, 1010...1016,
        ]
        if pauses.contains(where: { $0.contains(t) }) { return room(t) }
        return speech(t, level: 0.32)
    }

    /// Eight seconds of room tone before anyone speaks — the classic "cut the head off"
    /// case — then talk, a music sting for an ad break, then talk again.
    private static func podcast(_ t: Double, _ duration: Double) -> Float {
        if t < 8 { return room(t) }
        if (96...121).contains(t) { return chord(t, level: 0.55) }
        if (121...124).contains(t) { return room(t) }
        return speech(t, level: 0.38)
    }

    /// A quiet intro, a loud body, a breakdown, a loud outro. Wide dynamic range, so the
    /// envelope is doing real work.
    private static func music(_ t: Double, _ duration: Double) -> Float {
        let level: Double
        switch t {
        case ..<12:   level = 0.08 + 0.12 * (t / 12)
        case ..<48:   level = 0.72
        case ..<62:   level = 0.22
        default:      level = 0.80
        }
        return chord(t, level: level)
    }

    /// A pure 440 Hz sine — a flat rectangle at any zoom, and the degenerate case for
    /// "can you find your place in the waveform".
    private static func tone(_ t: Double, _ duration: Double) -> Float {
        Float(0.36 * sin(2 * .pi * 440 * t))
    }

    // MARK: - Generators

    private static func room(_ t: Double) -> Float {
        Float(0.004 * (noise(t) + 0.4 * sin(2 * .pi * 60 * t)))
    }

    /// Bandpass-ish noise under a syllable-rate envelope. Not speech, but it has speech's
    /// silhouette: bursts of roughly a syllable, phrases with gaps between them.
    private static func speech(_ t: Double, level: Double) -> Float {
        let syllable = max(0, sin(2 * .pi * 3.7 * t))
        let phrase = max(0, sin(2 * .pi * 0.19 * t + 0.9))
        let breath = 0.5 + 0.5 * sin(2 * .pi * 0.043 * t)
        let carrier = 0.6 * noise(t) + 0.4 * sin(2 * .pi * (170 + 40 * sin(2 * .pi * 1.3 * t)) * t)
        return Float(level * breath * phrase * pow(syllable, 1.6) * carrier + Double(room(t)))
    }

    /// Sustained chord plus a transient on every beat, so there is something to aim at.
    private static func chord(_ t: Double, level: Double) -> Float {
        let beat = t.truncatingRemainder(dividingBy: 0.5)
        let hit = exp(-beat * 26) * noise(t) * 0.5
        let body = sin(2 * .pi * 110 * t) + 0.7 * sin(2 * .pi * 165 * t) + 0.5 * sin(2 * .pi * 220 * t)
        let swell = 0.75 + 0.25 * sin(2 * .pi * 0.11 * t)
        return Float(level * swell * (body / 2.2 + hit))
    }

    /// Deterministic value noise — no RNG, so regenerating gives byte-identical fixtures.
    private static func noise(_ t: Double) -> Double {
        let x = sin(t * 12_9898.0) * 43_758.5453
        return 2 * (x - x.rounded(.down)) - 1
    }

    // MARK: - Writing

    static func ensureLibrary() throws {
        let dir = Library.folder
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        for spec in specs {
            let url = dir.appending(path: "\(spec.source) 2026-08-23 at \(spec.clock).caf")
            guard !FileManager.default.fileExists(atPath: url.path) else { continue }
            try Diag.time("fixture \(spec.source) \(Int(spec.seconds))s") {
                try write(spec, to: url)
            }
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
                let s = spec.shape(t, spec.seconds)
                left[i] = s
                // A touch of stereo so the two lanes are not identical rectangles.
                right[i] = s * Float(0.82 + 0.18 * sin(2 * .pi * 0.07 * t))
            }
            try file.write(from: buffer)
            written += n
        }
    }
}
