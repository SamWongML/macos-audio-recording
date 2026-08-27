//
//  RecordingController.swift
//  AppTape
//

import AppKit
import Observation

/// The main-actor coordinator between the panel's Source choice, the Capture Engine, the
/// status-item transport, and the editor. It is the observation the menu bar renders and
/// the panel drives; the realtime and file work all live below it in `CaptureEngine`.
@MainActor
@Observable
final class RecordingController {
    static let shared = RecordingController()

    /// Armed and capturing (from the press, through the armed-waiting window, to stop). What
    /// the status item keys its recording state off.
    private(set) var isRecording = false
    /// The Source being captured, for the status item's tooltip and the panel's row state.
    private(set) var recordingSourceID: String?
    /// Master duration in seconds, read off the engine's frame count on a timer — so it sits
    /// at 0 (menu bar `00:00`) until the first sound (ADR-0016).
    private(set) var elapsed: TimeInterval = 0

    private var engine: CaptureEngine?
    private var timer: Timer?

    /// `01:23`, or `1:02:03` past the hour. Frozen at `00:00` through the armed window.
    var elapsedText: String {
        let total = Int(elapsed)
        let (hours, minutes, seconds) = (total / 3600, (total % 3600) / 60, total % 60)
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)
    }

    /// Begins capturing a Source. Optimistically flips to the recording state at once so the
    /// menu bar responds to the press, then builds the engine off the main thread — tap
    /// creation blocks and can raise the TCC prompt (issue #12).
    func start(_ source: Source) {
        guard !isRecording, !source.processObjectIDs.isEmpty else { return }
        isRecording = true
        recordingSourceID = source.bundleID
        elapsed = 0

        let ids = source.processObjectIDs
        let name = source.name
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let engine = try CaptureEngine(processObjectIDs: ids, sourceName: name)
                Task { @MainActor in self.attach(engine) }
            } catch {
                Task { @MainActor in self.failStart() }
            }
        }
    }

    /// Stops and finalizes. The UI returns to idle at once, then the engine is torn down off
    /// the main thread — `CaptureEngine.stop()` drains the ring and closes the file, which may
    /// block, and the main thread is the one that must not (ADR-0003). The editor opens on the
    /// Recording just made, once it is finalized — but only if there was one (arm-then-never-
    /// play opens nothing, ADR-0016).
    func stop() {
        guard isRecording else { return }
        isRecording = false
        recordingSourceID = nil
        timer?.invalidate()
        timer = nil
        elapsed = 0

        // Engine may still be building (stopped mid-arm): `attach` will orphan-stop it. Only
        // finalize one we actually hold.
        guard let engine else { return }
        self.engine = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let result = engine.stop()
            if result != nil {
                Task { @MainActor in EditorPresenter.shared.open() }
            }
        }
    }

    private func attach(_ engine: CaptureEngine) {
        // The user may have stopped during the (brief) build. If so, this engine is already
        // orphaned — tear it down (off-main; teardown can block) rather than leave a tap running.
        guard isRecording else {
            DispatchQueue.global(qos: .userInitiated).async { engine.stop() }
            return
        }
        self.engine = engine
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let engine = self.engine else { return }
                self.elapsed = engine.elapsed
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// The tap could not be built (denied grant, no output device, …). Denial *inference* is
    /// issue #14's; here we just return cleanly to idle rather than sit in a fake recording
    /// state.
    private func failStart() {
        isRecording = false
        recordingSourceID = nil
        elapsed = 0
    }
}
