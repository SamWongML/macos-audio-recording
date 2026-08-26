//  PROTOTYPE — throwaway playback. AVAudioEngine + AVAudioPlayerNode, playing a frame range
//  straight off the master with scheduleSegment(_:startingFrame:frameCount:atTime:).
//
//  The playhead is published from a 30 Hz timer onto an @Observable, not read out of the
//  audio graph by the view — same reason as the waveform (issue #6).

import AVFoundation
import Observation

/// What "play" means. The variants deliberately disagree, because this is one of the
/// sharper questions in issue #7.
enum PlayScope {
    /// Whole Recording; the playhead runs through the trimmed-out parts.
    case whole
    /// Only the Trim, looping at the out point — a preview of what Export will produce.
    case trimLooping
    /// From wherever the playhead is to the end, tape-deck style.
    case fromPlayhead
}

@MainActor @Observable
final class Player {
    private(set) var isPlaying = false
    /// Seconds into the Recording. Read by every playhead on screen.
    private(set) var position: Double = 0
    private(set) var recording: Recording?

    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    /// The audition path. #25's whole point: what you hear must be what you Export, so the
    /// combined Loudness-correction + Gain (one scalar, in dB — ADR-0013) is applied here,
    /// on the graph, not only on the written file. There is no separate monitor volume.
    /// `AVAudioUnitEQ`'s `globalGain` is a plain wideband gain in dB (−96…+24), which is
    /// exactly the pure scalar multiply ADR-0013 requires — no dynamics, no limiter.
    private let eq = AVAudioUnitEQ(numberOfBands: 0)
    private var file: AVAudioFile?
    private var segmentStart: Double = 0
    private var scope: PlayScope = .whole
    private var ticker: Timer?
    private var scheduledEnd: Double = 0

    init() {
        engine.attach(node)
        engine.attach(eq)
    }

    /// Set the audition gain in dB. Clamped to the unit's range; the correction never asks
    /// for more than +12 and respects the −3 dBTP ceiling, but a manual Gain on top can, and
    /// clipping there is honest — it is what the Export would do too.
    func setAuditionGain(db: Double) {
        eq.globalGain = Float(min(max(db, -96), 24))
    }

    func load(_ recording: Recording) {
        guard self.recording?.url != recording.url else { return }
        stop()
        self.recording = recording
        file = try? AVAudioFile(forReading: recording.url)
        position = recording.trim.lowerBound
        if let file {
            engine.disconnectNodeOutput(node)
            engine.disconnectNodeOutput(eq)
            // macOS 27 deprecated every non-throwing connect/play on AVAudioEngine and
            // AVAudioPlayerNode in favour of error-returning twins — and renamed them in
            // Swift, so `try engine.connect(...)` does not exist. It is `connectNode`.
            // node → eq (the audition gain) → mainMixer.
            try? engine.connectNode(node, to: eq, format: file.processingFormat)
            try? engine.connectNode(eq, to: engine.mainMixerNode, format: file.processingFormat)
        }
    }

    func toggle(scope: PlayScope) {
        isPlaying ? pause() : play(scope: scope)
    }

    func play(scope: PlayScope) {
        guard let file, let recording else { return }
        self.scope = scope

        let range: ClosedRange<Double>
        switch scope {
        case .whole:        range = 0...recording.duration
        case .trimLooping:  range = recording.trim.range
        case .fromPlayhead: range = min(position, recording.duration - 0.05)...recording.duration
        }
        var from = position
        if from < range.lowerBound - 0.001 || from >= range.upperBound - 0.001 { from = range.lowerBound }

        let rate = recording.sampleRate
        let startFrame = AVAudioFramePosition(from * rate)
        let frames = AVAudioFrameCount(max(1, (range.upperBound - from) * rate))
        guard startFrame + AVAudioFramePosition(frames) <= file.length else { return }

        node.stop()
        segmentStart = from
        scheduledEnd = range.upperBound
        node.scheduleSegment(file, startingFrame: startFrame, frameCount: frames, at: nil)

        do {
            if !engine.isRunning { try engine.start() }
        } catch {
            Diag.note("engine start failed: \(error)")
            return
        }
        do { try node.playAudio() } catch {
            Diag.note("playAudio failed: \(error)")
            return
        }
        isPlaying = true
        startTicking()
    }

    func pause() {
        node.pause()
        isPlaying = false
        ticker?.invalidate(); ticker = nil
    }

    func stop() {
        node.stop()
        engine.pause()
        isPlaying = false
        ticker?.invalidate(); ticker = nil
    }

    /// Scrubbing: move the playhead, and if it was playing, re-schedule from the new point.
    func seek(to seconds: Double) {
        guard let recording else { return }
        let clamped = min(max(0, seconds), recording.duration)
        position = clamped
        guard isPlaying else { return }
        let scope = self.scope
        node.stop()
        play(scope: scope)
    }

    private func startTicking() {
        ticker?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func tick() {
        Diag.hit("playheadTick")
        guard let nodeTime = node.lastRenderTime,
              let playerTime = node.playerTime(forNodeTime: nodeTime) else { return }
        let elapsed = Double(playerTime.sampleTime) / playerTime.sampleRate
        position = segmentStart + elapsed

        guard position >= scheduledEnd - 0.02 else { return }
        switch scope {
        case .trimLooping:
            position = recording?.trim.lowerBound ?? 0
            play(scope: .trimLooping)
        case .whole, .fromPlayhead:
            pause()
            position = scheduledEnd
        }
    }
}
