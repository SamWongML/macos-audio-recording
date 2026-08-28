//
//  AudioPlayer.swift
//  AppTape
//

import AVFoundation
import Observation

/// Editor playback: an `AVAudioEngine` + `AVAudioPlayerNode` playing a frame range straight off
/// the master with `scheduleSegment`. **Play loops the Trim** — a preview of exactly what Export
/// will produce (issue #7, variant O/Q). The playhead is published from a 30 Hz timer onto this
/// `@Observable`, not read out of the audio graph by the view (issue #6).
@MainActor
@Observable
final class AudioPlayer {
    private(set) var isPlaying = false
    /// Seconds into the Recording. Read by the playhead on screen.
    private(set) var position: Double = 0
    private(set) var recording: Recording?

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let node = AVAudioPlayerNode()
    @ObservationIgnored private var file: AVAudioFile?
    @ObservationIgnored private var segmentStart: Double = 0
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var scheduledEnd: Double = 0

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
            // AVAudioPlayerNode in favour of error-returning twins — and renamed them in Swift,
            // so `try engine.connect(...)` does not exist. It is `connectNode` / `playAudio`.
            // Best-effort: a failed connect just leaves the graph unable to play, which the next
            // `play()` reports by staying stopped — nothing here is worth trapping the editor over.
            try? engine.connectNode(node, to: engine.mainMixerNode, format: file.processingFormat)
        }
    }

    func toggle() { isPlaying ? pause() : play() }

    /// Plays the current Trim, looping at the out point.
    func play() {
        guard let file, let recording else { return }
        let range = recording.trim.range
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
            try node.playAudio()
        } catch {
            // Playback is best-effort: if the engine or node refuses to start, leave the
            // transport showing stopped rather than surface an error for a preview.
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
        position = min(max(0, seconds), recording.duration)
        guard isPlaying else { return }
        node.stop()
        play()
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
        guard let nodeTime = node.lastRenderTime,
              let playerTime = node.playerTime(forNodeTime: nodeTime) else { return }
        position = segmentStart + Double(playerTime.sampleTime) / playerTime.sampleRate

        guard position >= scheduledEnd - 0.02 else { return }
        // Loop the Trim: jump the playhead back to the in point and reschedule.
        position = recording?.trim.lowerBound ?? 0
        play()
    }
}
