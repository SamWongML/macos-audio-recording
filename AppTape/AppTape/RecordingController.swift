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

    /// True once a Recording has actually captured audio this launch. It gates the wedge
    /// timeout: the first bring-up is cancellable-not-timed so a ~90 s TCC prompt cannot abort
    /// it, and only after a success does a slow bring-up become a wedge worth timing out
    /// (ADR-0008, ADR-0010). A fact about *capture*, held in memory only — nothing about
    /// permission is ever persisted (ADR-0008).
    private(set) var hasCompletedACapture = false

    /// Set when a denied System Audio Recording grant is inferred (ADR-0008); drives the panel's
    /// recovery banner. Cleared on the next record press — retry is simply pressing record again.
    private(set) var permissionRecovery = false

    /// The Library file currently being written, once the first sound has created it. The editor
    /// refuses to export this one: its `.caf` is still growing in place and its Trim end is
    /// undefined until Stop (ADR-0012). Nil when nothing is capturing, or before the first sound.
    private(set) var capturingURL: URL?

    /// Whether `recording` is the one being captured right now, and so not exportable (ADR-0012).
    func isCapturing(_ recording: Recording) -> Bool {
        isRecording && capturingURL == recording.url
    }

    /// The wedge timeout that applies to bring-up *after* the first successful capture, when the
    /// TCC prompt can no longer appear and a slow start is a hang, not a human reading (ADR-0010).
    static let wedgeTimeout: TimeInterval = 10

    private var engine: CaptureEngine?
    private var timer: Timer?
    /// The post-first-capture wedge timer, armed during bring-up only when `hasCompletedACapture`.
    private var buildTimeout: Timer?
    /// Bumped on every start and stop. Guards a slow, cancelled, or timed-out bring-up from
    /// attaching its engine to a *later* attempt — the blocked Core Audio call cannot be
    /// interrupted, so whatever it eventually returns is matched against the generation that
    /// asked for it and discarded if the world has moved on (ADR-0010).
    private var generation = 0

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
        permissionRecovery = false   // retry clears the last denial's banner
        isRecording = true
        recordingSourceID = source.bundleID
        elapsed = 0
        generation += 1
        let gen = generation

        // The wedge timeout is armed only after the first successful capture. On the first
        // Recording bring-up is cancellable-not-timed, so it can block ~90 s behind the TCC
        // prompt without aborting; a second click is the only way out then (ADR-0008/0010).
        if hasCompletedACapture {
            let timeout = Timer(timeInterval: Self.wedgeTimeout, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.abandon(generation: gen) }
            }
            RunLoop.main.add(timeout, forMode: .common)
            buildTimeout = timeout
        }

        let ids = source.processObjectIDs
        let name = source.name
        // Set at init, before the engine's writer thread starts, so a denial inferred before
        // `attach` runs is still delivered. `handleDenial` in turn does not depend on `attach`
        // having set `self.engine`, so the signal is never dropped even if the main actor is
        // slow to pick up `attach` — together they close the gap the 3 s window leaves open.
        let onDenial: @Sendable () -> Void = { [weak self] in
            guard let self else { return }
            Task { @MainActor in self.handleDenial(generation: gen) }
        }
        // Learn the growing master's path when the first sound creates it, so the editor can refuse
        // to export the still-capturing Recording (ADR-0012). Guarded by generation like the rest.
        let onMasterCreated: @Sendable (URL) -> Void = { [weak self] url in
            guard let self else { return }
            Task { @MainActor in
                guard gen == self.generation, self.isRecording else { return }
                self.capturingURL = url
            }
        }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let engine = try CaptureEngine(processObjectIDs: ids, sourceName: name,
                                               onDenialInferred: onDenial,
                                               onMasterCreated: onMasterCreated)
                Task { @MainActor in self.attach(engine, generation: gen) }
            } catch {
                Task { @MainActor in self.abandon(generation: gen) }
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
        returnToIdle()

        // Engine may still be building (a second click abandoned the attempt mid-bring-up):
        // `attach` will orphan-stop it, and the bumped generation makes that certain. Only
        // finalize one we actually hold.
        guard let engine else { return }
        self.engine = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let result = engine.stop()
            if let result {
                Task { @MainActor in
                    // The grant is now known good, so a later slow bring-up is a wedge to time
                    // out rather than a human at the prompt (ADR-0010).
                    self.hasCompletedACapture = true
                    // Open the editor on the Recording just finalized (ADR-0016).
                    EditorPresenter.shared.open(selecting: result.url)
                }
            }
        }
    }

    private func attach(_ engine: CaptureEngine, generation gen: Int) {
        // The attempt may have ended during the (usually brief, but on the first run possibly
        // ~90 s) build — a second-click cancel, a wedge timeout, or a whole new attempt. If the
        // world has moved on, this engine is orphaned: tear it down off-main (teardown can block)
        // rather than leave a tap running.
        guard gen == generation, isRecording else {
            DispatchQueue.global(qos: .userInitiated).async { engine.stop() }
            return
        }
        buildTimeout?.invalidate()
        buildTimeout = nil
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

    /// A denied grant was inferred (ADR-0008): end the Recording, discard the engine (which
    /// removes any all-zero file), and raise the panel's recovery banner. No file is opened —
    /// unlike a fault-stopped Recording, a denial produced no first sound and so no Recording.
    ///
    /// It must not depend on `attach` having run: the writer thread can infer denial before the
    /// main actor picks up `attach` under load, and if it does, `self.engine` is still nil. So we
    /// return to idle and raise recovery regardless — and if we do not yet hold the engine, the
    /// in-flight `attach` for this (now stale) generation orphan-stops it, which is equivalent to
    /// `discard` here since a denied Recording created no file to remove (ADR-0016 head elision).
    private func handleDenial(generation gen: Int) {
        guard gen == generation, isRecording else { return }
        returnToIdle()
        if let engine {
            self.engine = nil
            DispatchQueue.global(qos: .userInitiated).async { engine.discard() }
        }
        permissionRecovery = true
    }

    /// Bring-up was abandoned before it produced an engine — a build error, or the wedge timeout
    /// firing after the first capture. Return cleanly to idle; any engine the blocked call later
    /// hands back attaches against a stale generation and tears itself down.
    private func abandon(generation gen: Int) {
        guard gen == generation, isRecording else { return }
        returnToIdle()
    }

    /// The common return-to-idle: clears the recording state and both timers, and bumps the
    /// generation so any in-flight bring-up for the old attempt orphans itself.
    private func returnToIdle() {
        isRecording = false
        recordingSourceID = nil
        capturingURL = nil
        timer?.invalidate()
        timer = nil
        buildTimeout?.invalidate()
        buildTimeout = nil
        elapsed = 0
        generation += 1
    }
}
