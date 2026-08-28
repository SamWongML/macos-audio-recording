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

    /// The menu bar's disk tier (ADR-0009): amber at 3 hours of Runway, whole item, no glyph. Driven
    /// by the 5 s guard poll while recording; nominal at rest.
    private(set) var runwayTier: RunwayGuard.Tier = .nominal

    /// Set when a record press is refused below the 2 GB floor (ADR-0009); drives the panel's one
    /// blocking-message surface, sharing it with `permissionRecovery` — the panel carries at most one
    /// blocking reason at a time. Cleared on the next successful start, and by a denial taking the
    /// surface. Its action opens Finder at the Library.
    private(set) var startRefusal: DiskGuardRefusal?

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
    /// The disk guard's 5 s `statfs` poll, live only while a Recording is attached (ADR-0009). Off
    /// the realtime IOProc and the writer thread — one quick syscall on the main actor.
    private var guardTimer: Timer?
    /// The Runway tier/warning reducer for the current Recording, reset at each start so hysteresis
    /// never carries across Recordings.
    private var runwayGuard = RunwayGuard()
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

        // The start policy against the disk (ADR-0009). The rate is a pre-tap estimate — no tap
        // exists yet to report its real format — corrected by the first real poll a few seconds
        // later; an unverifiable volume (nil) is neither refused nor pre-ambered, matching the
        // running guard, which never ends on a volume it cannot stat.
        let free = DiskSpace.freeBytesForLibraryVolume()
        let startDecision = free.map {
            RunwayGuard.startDecision(freeBytes: $0, ratePerSecond: RunwayGuard.nominalRatePerSecond)
        }

        // Refuse below the floor: beginning a Recording the guard kills within a minute leaves junk
        // in the Library and teaches nothing. The refusal raises the panel's one blocking-message
        // surface, whose action opens Finder at the Library.
        if startDecision == .refuse, let free {
            startRefusal = DiskGuardRefusal(freeBytes: free)
            permissionRecovery = false
            return
        }

        startRefusal = nil
        permissionRecovery = false   // retry clears the last denial's banner
        isRecording = true
        recordingSourceID = source.bundleID
        elapsed = 0
        generation += 1
        let gen = generation

        // Begin amber if already inside the 3-hour tier, so a Recording the guard would paint amber
        // within seconds does not flash green first (ADR-0009). The first real poll re-decides with
        // the tap's own byte rate, so an off estimate only ever costs a brief wrong colour.
        let amberStart = startDecision == .allowAmber
        runwayGuard = RunwayGuard(tier: amberStart ? .amber : .nominal)
        runwayTier = amberStart ? .amber : .nominal

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
        // The Recording ended itself — recovery exhausted, a format mismatch, or a >30 s gap: one of
        // the four unrequested ends (ADR-0010). The engine has already finalized the file; reclaim it
        // and tell the user why, naming the reason and opening the editor on the notification's click.
        let onEnded: @Sendable (RecordingEndReason) -> Void = { [weak self] reason in
            guard let self else { return }
            Task { @MainActor in self.finalize(reason: reason, generation: gen) }
        }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let engine = try CaptureEngine(processObjectIDs: ids, sourceName: name,
                                               onDenialInferred: onDenial,
                                               onMasterCreated: onMasterCreated,
                                               onEnded: onEnded)
                Task { @MainActor in self.attach(engine, generation: gen) }
            } catch {
                Task { @MainActor in self.abandon(generation: gen) }
            }
        }
    }

    /// The user pressed stop. The UI returns to idle at once, then the engine is torn down off the
    /// main thread — one of the two *requested* ends (ADR-0007). The editor opens on the Recording
    /// just made, once finalized — but only if there was one (arm-then-never-play opens nothing).
    func stop() {
        finalize(reason: .userStopped, generation: generation)
    }

    /// System sleep or fast user switching (folded together, ADR-0007): end the Recording **on the
    /// notification**, while the machine is still awake, so the file is finalized at its last real
    /// sample and there is no gap to reconcile — no Seam. One of the four unrequested ends, so it
    /// names its reason.
    func endForSleep() {
        finalize(reason: .sleep, generation: generation)
    }

    /// App quit or logout: finalize and save unwarned, as ADR-0004 accepts for a left-click. A
    /// requested end — no notification, no window. Unlike the other ends this finalizes
    /// **synchronously on the main thread**, because the process is about to exit: the writer must
    /// finish draining, close the CAF, and write the Seams xattr before `applicationWillTerminate`
    /// returns. The CAF is crash-safe even if the OS kills us first (ADR-0003), but a synchronous
    /// close also secures the Seam mark and the tail. No main hops happen inside a quit finalize
    /// (`onEnded` fires only on a self-end), so blocking here cannot deadlock.
    func endForQuit() {
        guard isRecording else { return }
        returnToIdle()
        guard let engine else { return }
        self.engine = nil
        _ = engine.stop()
    }

    /// The one finalization path every end funnels through (ADR-0007). Returns to idle at once, then
    /// tears the engine down off the main thread — `stop()` drains the ring and closes the file,
    /// which may block, and the main thread must not (ADR-0003). If the engine had already ended
    /// itself on a fault, its own reason wins over the caller's.
    private func finalize(reason: RecordingEndReason, generation gen: Int) {
        guard gen == generation, isRecording else { return }
        returnToIdle()

        // Engine may still be building (a second click abandoned the attempt mid-bring-up): `attach`
        // will orphan-stop it, and the bumped generation makes that certain. Only finalize one we hold.
        guard let engine else { return }
        self.engine = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let result = engine.stop()
            let effective = engine.endReason ?? reason
            Task { @MainActor in self.didFinalize(result: result, reason: effective) }
        }
    }

    /// Back on the main actor with the finalized file (or nil for arm-then-never-play). Tells the
    /// user what happened per the end's kind (ADR-0009/0010).
    private func didFinalize(result: CaptureResult?, reason: RecordingEndReason) {
        // A Recording that captured audio — even one a fault ended — means the grant is known good,
        // so a later slow bring-up is a wedge to time out rather than a human at the prompt (ADR-0010).
        if result != nil { hasCompletedACapture = true }
        guard let result else { return }   // arm-then-never-play: nothing saved, nothing to tell.

        switch reason {
        case .userStopped:
            // The first *completed* Recording is where notification authorization is requested, so a
            // later unrequested end has a channel — never stacked onto a failure (ADR-0009).
            FaultNotifier.requestAuthorizationOnce()
            EditorPresenter.shared.open(selecting: result.url)
        case .quit:
            break   // you asked for it; the app is leaving. No window, no notification.
        case .diskGuard, .recoveryExhausted, .formatMismatch, .sleep:
            // Name the reason and open the editor on the click — or directly, if auth is absent.
            FaultNotifier.recordingEnded(reason: reason, recordingURL: result.url)
        }
    }

    /// Registers the lifecycle ends that arrive as notifications: sleep, fast user switching, and
    /// logout/power-off. Idempotent; called once from the app delegate. Quit itself is caught in
    /// `applicationWillTerminate`. Uses the block API (like `LibraryStore`) because this is a plain
    /// `@Observable`, not an `NSObject`, so a selector target would never be dispatched.
    func installLifecycleObservers() {
        guard !installedLifecycleObservers else { return }
        installedLifecycleObservers = true
        let workspace = NSWorkspace.shared.notificationCenter
        // Sleep and fast user switching are folded together — both end the Recording as `.sleep`.
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.endForSleep() }
            }
        }
        // Logout / power-off is the quit end arriving before `applicationWillTerminate`.
        workspace.addObserver(forName: NSWorkspace.willPowerOffNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.endForQuit() }
        }
    }

    private var installedLifecycleObservers = false

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

        // The disk guard's 5 s poll (ADR-0009). Run once immediately so amber/end reflect the tap's
        // real byte rate without waiting a full interval — the pre-seeded amber used a nominal rate.
        let guardTimer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluateRunwayGuard() }
        }
        RunLoop.main.add(guardTimer, forMode: .common)
        self.guardTimer = guardTimer
        evaluateRunwayGuard()
    }

    /// One Runway reading (ADR-0009): fold current free space and the master's byte rate into the
    /// guard, then act — paint amber, post the 30-minute warning once, or end at the floor. A volume
    /// that cannot be stat'd is skipped, never treated as empty, so an unverifiable disk never ends a
    /// Recording.
    private func evaluateRunwayGuard() {
        guard isRecording, let engine else { return }
        guard let free = DiskSpace.freeBytesForLibraryVolume() else { return }
        let decision = runwayGuard.receive(freeBytes: free, ratePerSecond: engine.bytesPerSecond)
        runwayTier = decision.tier
        if decision.shouldWarn { FaultNotifier.runwayLow() }
        if decision.shouldEnd { finalize(reason: .diskGuard, generation: generation) }
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
        startRefusal = nil   // the panel carries at most one blocking reason (ADR-0009)
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
        guardTimer?.invalidate()
        guardTimer = nil
        runwayTier = .nominal
        elapsed = 0
        generation += 1
    }
}
