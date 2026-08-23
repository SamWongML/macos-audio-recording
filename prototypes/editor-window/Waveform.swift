//  PROTOTYPE — throwaway. Builds a peak envelope off the CAF master and draws it in a Canvas.
//
//  There is no first-party waveform view anywhere in the macOS 27 SDK (issue #4), so this is
//  the sanctioned path: AVAudioFile -> downsample -> Canvas.
//
//  The trap from issue #6 applies here too. A Canvas only redraws when its *inputs* change,
//  so the envelope is published as a plain value the view stores, never read out of a
//  buffer the view cannot observe.

import AVFoundation
import SwiftUI

/// Min/max/RMS per bucket of `framesPerBucket`, over a mono mixdown of the master.
struct Envelope: Equatable, Sendable {
    var framesPerBucket: Int = 256
    var sampleRate: Double = 48_000
    var mins: [Float] = []
    var maxs: [Float] = []
    var rms: [Float] = []
    /// False while the background pass is still reading — the view draws what has arrived.
    var complete = false

    var seconds: Double { Double(mins.count * framesPerBucket) / sampleRate }
    var isEmpty: Bool { mins.isEmpty }

    /// One column per pixel over `range`, reduced from whatever buckets it spans.
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
    }

    /// Rescale a slice so its loudest point fills the view. Only ever used by the loupe:
    /// the main lane must keep an absolute scale or the picture would lie about level.
    static func normalised(_ columns: [Column]) -> [Column] {
        let peak = columns.reduce(Float(0)) { Swift.max($0, Swift.max($1.max, -$1.min)) }
        guard peak > 0.0001, peak < 0.9 else { return columns }
        let k = 0.9 / peak
        return columns.map { Column(min: $0.min * k, max: $0.max * k, rms: $0.rms * k) }
    }
}

/// Fills in each Recording's own envelope. Deliberately *not* a store keyed by URL: a row
/// in a lazy `List` does not pick up a change to a dictionary living on some other object,
/// and the first pass of this prototype proved it — the sidebar sparklines never appeared
/// while the identical view inside a non-lazy `HStack` drew fine. Observing the element you
/// were handed is the shape SwiftUI actually tracks.
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

        let started = DispatchTime.now().uptimeNanoseconds
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
                var mn: Float = 0, mx: Float = 0, sq: Float = 0
                for f in i..<end {
                    var v: Float = 0
                    for c in 0..<channelCount { v += channels[c][f] }
                    v /= Float(channelCount)
                    mn = Swift.min(mn, v); mx = Swift.max(mx, v); sq += v * v
                }
                env.mins.append(mn); env.maxs.append(mx)
                env.rms.append((sq / Float(end - i)).squareRoot())
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
        let ms = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
        Diag.note(String(format: "envelope %@  %.1fs audio  %d buckets  %.0f ms",
                         url.lastPathComponent,
                         Double(file.length) / format.sampleRate,
                         env.mins.count, ms))
    }

    /// The loupe re-reads on every drag frame, so the open file is held rather than
    /// reopened sixty times a second.
    nonisolated(unsafe) private static var loupeFile: (url: URL, file: AVAudioFile)?
    private static let loupeLock = NSLock()

    /// Raw frames for the loupe — a narrow window read straight off the file, no envelope.
    nonisolated static func rawPeaks(url: URL, around centre: Double, span: Double, columns: Int) -> [Envelope.Column] {
        guard columns > 0 else { return [] }
        loupeLock.lock()
        if loupeFile?.url != url { loupeFile = (try? AVAudioFile(forReading: url)).map { (url, $0) } }
        let cached = loupeFile?.file
        loupeLock.unlock()
        guard let file = cached else { return [] }
        let rate = file.processingFormat.sampleRate
        let start = max(0, AVAudioFramePosition((centre - span / 2) * rate))
        let frames = AVAudioFrameCount(min(Double(file.length - start), span * rate))
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames)
        else { return [] }
        file.framePosition = start
        guard (try? file.read(into: buffer, frameCount: frames)) != nil,
              let channels = buffer.floatChannelData else { return [] }

        let n = Int(buffer.frameLength)
        let channelCount = Int(file.processingFormat.channelCount)
        let per = max(1, n / columns)
        var out = [Envelope.Column]()
        var i = 0
        while i < n {
            let end = min(i + per, n)
            var mn: Float = 0, mx: Float = 0, sq: Float = 0
            for f in i..<end {
                var v: Float = 0
                for c in 0..<channelCount { v += channels[c][f] }
                v /= Float(channelCount)
                mn = Swift.min(mn, v); mx = Swift.max(mx, v); sq += v * v
            }
            out.append(.init(min: mn, max: mx, rms: (sq / Float(end - i)).squareRoot()))
            i = end
        }
        return out
    }
}

// MARK: - Drawing

/// The waveform itself. Deliberately dumb: it takes columns as a stored value and draws them.
struct WaveformShape: View {
    var columns: [Envelope.Column]
    var peakStyle: AnyShapeStyle
    var bodyStyle: AnyShapeStyle
    /// Amplitude is drawn on a mild power curve; linear peaks make ordinary speech invisible
    /// next to one loud transient. 0.65 is close to how Logic and Audacity look.
    var curve: Double = 0.65

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, size in
            Diag.hit("canvasDraw")
            guard !columns.isEmpty else { return }
            let mid = size.height / 2
            let scale = size.height / 2
            let step = size.width / Double(columns.count)

            context.fill(path(columns.map { ($0.min, $0.max) },
                              size: size, mid: mid, scale: scale, step: step),
                         with: .style(peakStyle))
            context.fill(path(columns.map { (-$0.rms, $0.rms) },
                              size: size, mid: mid, scale: scale, step: step),
                         with: .style(bodyStyle))
        }
    }

    private func path(_ pairs: [(Float, Float)], size: CGSize, mid: Double, scale: Double, step: Double) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: mid))
        for (i, pair) in pairs.enumerated() {
            let v = shape(Double(pair.1))
            p.addLine(to: CGPoint(x: Double(i) * step, y: mid - max(v * scale, 0.5)))
        }
        for (i, pair) in pairs.enumerated().reversed() {
            let v = shape(Double(-pair.0))
            p.addLine(to: CGPoint(x: Double(i) * step, y: mid + max(v * scale, 0.5)))
        }
        p.closeSubpath()
        return p
    }

    private func shape(_ v: Double) -> Double { pow(min(1, max(0, v)), curve) }
}

/// Same picture, drawn as a `Shape` instead of a `Canvas`.
///
/// It exists because a `Canvas` inside a `List` row draws *nothing* on macOS 27 — verified
/// with the envelope fully loaded (225,000 buckets), the frame laid out at its requested
/// 46x20, and a red debug border proving the space was reserved. The identical view in a
/// non-lazy `HStack` draws fine. A `Shape` goes through the ordinary render path and works.
struct WaveformPath: Shape {
    var columns: [Envelope.Column]
    var curve: Double = 0.65

    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard !columns.isEmpty else { return p }
        let mid = rect.midY, scale = rect.height / 2
        let step = rect.width / Double(columns.count)
        p.move(to: CGPoint(x: 0, y: mid))
        for (i, column) in columns.enumerated() {
            let v = pow(min(1, max(0, Double(column.max))), curve)
            p.addLine(to: CGPoint(x: Double(i) * step, y: mid - Swift.max(v * scale, 0.5)))
        }
        for (i, column) in columns.enumerated().reversed() {
            let v = pow(min(1, max(0, Double(-column.min))), curve)
            p.addLine(to: CGPoint(x: Double(i) * step, y: mid + Swift.max(v * scale, 0.5)))
        }
        p.closeSubpath()
        return p
    }
}
