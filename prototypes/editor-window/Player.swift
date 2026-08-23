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
    private var file: AVAudioFile?
    private var segmentStart: Double = 0
    private var scope: PlayScope = .whole
    private var ticker: Timer?
    private var scheduledEnd: Double = 0

    init() {
        engine.attach(node)
    }

    func load(_ recording: Recording) {
        guard self.recording?.url != recording.url else { return }
        stop()
        self.recording = recording
        file = try? AVAudioFile(forReading: recording.url)
        position = recording.trim.lowerBound
        if let file {
            engine.disconnectNodeOutput(node)
            // macOS 27 deprecated every non-throwing connect/play on AVAudioEngine and
            // AVAudioPlayerNode in favour of error-returning twins — and renamed them in
            // Swift, so `try engine.connect(...)` does not exist. It is `connectNode`.
            try? engine.connectNode(node, to: engine.mainMixerNode, format: file.processingFormat)
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
        case .trimLooping:  range = recording.trim
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
