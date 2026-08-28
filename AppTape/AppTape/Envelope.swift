//
//  Envelope.swift
//  AppTape
//

import AVFoundation
import Foundation

/// The waveform is built `AVAudioFile → downsample → Canvas`, the sanctioned path (issue #4:
/// there is no first-party waveform view in the macOS 27 SDK). **There is no peak cache and no
/// sidecar file** — issue #7 measured a 20-minute Float32 master reducing in ~155 ms with `-O`,
/// so an on-disk artifact beside the CAF would buy nothing and would have to be invalidated and
/// garbage-collected, muddying ADR-0006's "the folder is the truth". The envelope is rebuilt
/// from the master each time it is needed.
///
/// (Watch out for the Debug build: the same reduce unoptimised is ~125× slower. A peak cache
/// looks mandatory in Debug and is not — it is the optimiser, not the algorithm.)
struct Envelope: Equatable, Sendable {
    var framesPerBucket: Int = 256
    var sampleRate: Double = 48_000
    var mins: [Float] = []
    var maxs: [Float] = []
    var rms: [Float] = []
    /// False while the background pass is still reading — the view draws what has arrived so a
    /// long Recording appears progressively rather than after a stall.
    var complete = false

    var seconds: Double { Double(mins.count * framesPerBucket) / sampleRate }
    var isEmpty: Bool { mins.isEmpty }

    /// One column per pixel over `range`, reduced from whatever buckets it spans. The lane asks
    /// for exactly its own width in columns, so the waveform **always fits the width**.
    func columns(over range: ClosedRange<Double>, count: Int) -> [Column] {
        guard count > 0, !mins.isEmpty else { return [] }
        let perBucket = Double(framesPerBucket) / sampleRate
        var out = [Column]()
        out.reserveCapacity(count)
        for i in 0..<count {
            let t0 = range.lowerBound + (range.upperBound - range.lowerBound) * Double(i) / Double(count)
            let t1 = range.lowerBound + (range.upperBound - range.lowerBound) * Double(i + 1) / Double(count)
            let lo = max(0, Int(t0 / perBucket))
            let hi = min(mins.count, max(lo + 1, Int((t1 / perBucket).rounded(.up))))
            guard lo < hi else { out.append(Column(min: 0, max: 0, rms: 0)); continue }
            var mn: Float = 0, mx: Float = 0, sum: Float = 0
            for b in lo..<hi {
                mn = Swift.min(mn, mins[b]); mx = Swift.max(mx, maxs[b]); sum += rms[b]
            }
            out.append(Column(min: mn, max: mx, rms: sum / Float(hi - lo)))
        }
        return out
    }

    struct Column: Equatable, Sendable {
        var min: Float, max: Float, rms: Float

        /// Reduce one bucket of frames `[from, to)` to a mono min/max/rms over the channels. The
        /// one place the mixdown lives — both the full scan and the loupe re-read go through it.
        /// `nonisolated` because both callers run off the main actor (a detached scan, a loupe
        /// re-read), and this is pure arithmetic over the buffer they hand it.
        nonisolated static func reduce(_ channels: UnsafePointer<UnsafeMutablePointer<Float>>,
                                       from: Int, to: Int, channelCount: Int) -> Column {
            var mn: Float = 0, mx: Float = 0, sq: Float = 0
            for f in from..<to {
                var v: Float = 0
                for c in 0..<channelCount { v += channels[c][f] }
                v /= Float(channelCount)
                mn = Swift.min(mn, v); mx = Swift.max(mx, v); sq += v * v
            }
            return Column(min: mn, max: mx, rms: (sq / Float(Swift.max(1, to - from))).squareRoot())
        }
    }

    /// Rescale a slice so its loudest point fills the view. Only ever used by the loupe: the
    /// main lane must keep an absolute scale or the picture would lie about level.
    static func normalised(_ columns: [Column]) -> [Column] {
        let peak = columns.reduce(Float(0)) { Swift.max($0, Swift.max($1.max, -$1.min)) }
        guard peak > 0.0001, peak < 0.9 else { return columns }
        let k = 0.9 / peak
        return columns.map { Column(min: $0.min * k, max: $0.max * k, rms: $0.rms * k) }
    }
}

/// Fills in each Recording's own envelope. Deliberately **not** a store keyed by URL: a row in
/// a lazy `List` does not pick up a change to a dictionary living on some other object (issue #6
/// proved it — sidebar sparklines never appeared while the identical view in a non-lazy `HStack`
/// drew fine). Observing the element you were handed is the shape SwiftUI actually tracks.
enum EnvelopeLoader {
    @MainActor
    static func load(_ recording: Recording) {
        guard recording.envelopeState == .idle else { return }
        recording.envelopeState = .building
        let url = recording.url
        Task.detached(priority: .userInitiated) {
            await scan(url: url) { partial in
                await MainActor.run { recording.envelope = partial }
            }
            await MainActor.run { recording.envelopeState = .done }
        }
    }

    /// Reads the master once, publishing roughly twenty times so a long Recording draws
    /// progressively instead of after a stall.
    private static func scan(url: URL, publish: @Sendable (Envelope) async -> Void) async {
        guard let file = try? AVAudioFile(forReading: url) else { return }
        let format = file.processingFormat
        let framesPerBucket = 256
        let chunk = AVAudioFrameCount(framesPerBucket * 512)   // 131072 frames ~ 2.7 s
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk) else { return }

        var env = Envelope(framesPerBucket: framesPerBucket, sampleRate: format.sampleRate)
        let bucketTotal = Int(file.length) / framesPerBucket + 1
        env.mins.reserveCapacity(bucketTotal)
        env.maxs.reserveCapacity(bucketTotal)
        env.rms.reserveCapacity(bucketTotal)

        let publishEvery = max(1, bucketTotal / 20)
        var sincePublish = 0

        while true {
            do { try file.read(into: buffer, frameCount: chunk) } catch { break }
            let n = Int(buffer.frameLength)
            if n == 0 { break }
            guard let channels = buffer.floatChannelData else { break }
            let channelCount = Int(format.channelCount)

            var i = 0
            while i < n {
                let end = min(i + framesPerBucket, n)
                let column = Envelope.Column.reduce(channels, from: i, to: end, channelCount: channelCount)
                env.mins.append(column.min); env.maxs.append(column.max); env.rms.append(column.rms)
                i = end
            }

            sincePublish += n / framesPerBucket
            if sincePublish >= publishEvery {
                sincePublish = 0
                let snapshot = env
                await publish(snapshot)
            }
        }

        env.complete = true
        await publish(env)
    }

    /// The loupe re-reads on every drag frame, so the open file is held rather than reopened
    /// sixty times a second.
    nonisolated(unsafe) private static var loupeFile: (url: URL, file: AVAudioFile)?
    nonisolated private static let loupeLock = NSLock()

    nonisolated private static func cachedFile(_ url: URL) -> AVAudioFile? {
        loupeLock.lock()
        defer { loupeLock.unlock() }
        if loupeFile?.url != url { loupeFile = (try? AVAudioFile(forReading: url)).map { (url, $0) } }
        return loupeFile?.file
    }

    /// Raw frames for the loupe, on a **fixed time grid** — the contract is the whole point.
    /// Returns exactly `columns` entries covering exactly `[centre - span/2, centre + span/2]`,
    /// bucketed on that time grid rather than on however many frames happened to be readable. So
    /// seconds-per-pixel is always `span / columns`, the middle column is always exactly
    /// `centre`, and the part of the window off either end of the file is *reported* (via
    /// `inside`) rather than faked, so it can be drawn as an edge instead of passing for silence.
    nonisolated static func loupeWindow(url: URL, centre: Double, span: Double, columns: Int) -> LoupeWindow {
        var window = LoupeWindow(columns: Array(repeating: .init(min: 0, max: 0, rms: 0), count: max(0, columns)),
                                 inside: 0..<0, span: span, centre: centre)
        guard columns > 0, let file = cachedFile(url) else { return window }

        let rate = file.processingFormat.sampleRate
        let duration = Double(file.length) / rate
        let t0 = centre - span / 2
        let dt = span / Double(columns)

        // Column i covers [t0 + i·dt, t0 + (i+1)·dt). Keep the ones that overlap the file.
        let first = max(0, Int(((0 - t0) / dt).rounded(.down)))
        let last = min(columns, Int(((duration - t0) / dt).rounded(.up)))
        guard first < last else { return window }

        let readStart = max(0, AVAudioFramePosition(((t0 + Double(first) * dt) * rate).rounded(.down)))
        let readEnd = min(file.length, AVAudioFramePosition(((t0 + Double(last) * dt) * rate).rounded(.up)))
        guard readEnd > readStart,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: AVAudioFrameCount(readEnd - readStart))
        else { return window }

        file.framePosition = readStart
        guard (try? file.read(into: buffer, frameCount: AVAudioFrameCount(readEnd - readStart))) != nil,
              let channels = buffer.floatChannelData else { return window }

        let available = Int(buffer.frameLength)
        let channelCount = Int(file.processingFormat.channelCount)

        for i in first..<last {
            let lo = Int(max(readStart, AVAudioFramePosition(((t0 + Double(i) * dt) * rate).rounded(.down))) - readStart)
            let hi = Int(min(readEnd, AVAudioFramePosition(((t0 + Double(i + 1) * dt) * rate).rounded(.up))) - readStart)
            let a = Swift.min(Swift.max(0, lo), available)
            let b = Swift.min(Swift.max(a, hi), available)
            guard b > a else { continue }

            window.columns[i] = Envelope.Column.reduce(channels, from: a, to: b, channelCount: channelCount)
        }

        window.inside = first..<last
        return window
    }
}

/// One loupe magnification: a fixed-scale slice of the master, with the part that falls off
/// either end of the file identified (`inside`) rather than silently drawn as silence.
struct LoupeWindow: Equatable {
    var columns: [Envelope.Column]
    /// Indices of `columns` that lie inside the file. Everything else is past an edge.
    var inside: Range<Int>
    var span: Double
    var centre: Double

    var secondsPerColumn: Double { columns.isEmpty ? 0 : span / Double(columns.count) }
    /// The fraction of the box, 0...1, where the file begins and ends.
    var insideFraction: ClosedRange<Double> {
        guard !columns.isEmpty else { return 0...0 }
        return Double(inside.lowerBound) / Double(columns.count)
            ... Double(inside.upperBound) / Double(columns.count)
    }
}
