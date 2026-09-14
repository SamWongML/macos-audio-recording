import Foundation
import Observation

/// One press's attempt at capturing. Minted at `start`, carried by every callback that press can
/// produce, and never reused — so a callback can always be matched against the world that asked
/// for it.
nonisolated private struct Attempt: Equatable, Sendable {
    let id: Int
}

/// One run of capture, start to stop: the coordination that 's six ends, 's denial
/// inference, 's Runway guard and 's generation rule all live in.
@MainActor
@Observable
final class CaptureRun {

    // MARK: - Where one attempt is in its life

    /// The run's whole state, as one value. `isRecording` and the generation counter used to be two
    /// variables that eight hand-written guards had to keep in step; here they cannot disagree,
    /// because both are read off this.
    private enum Phase {
        case idle
        /// Pressed, and the capture is being built. May sit here ~90 s behind the TCC prompt on the
        /// first run, which is why the wedge timeout is armed only after a success.
        case bringingUp(Attempt, pressedAt: TimeInterval)
        /// Built and attached. The master may or may not have begun — that is the first sound's
        /// business, not this one's.
        case capturing(Attempt, any Capturing, pressedAt: TimeInterval)

        var attempt: Attempt? {
            switch self {
            case .idle: nil
            case .bringingUp(let attempt, _): attempt
            case .capturing(let attempt, _, _): attempt
            }
        }

        var pressedAt: TimeInterval? {
            switch self {
            case .idle: nil
            case .bringingUp(_, let pressedAt): pressedAt
            case .capturing(_, _, let pressedAt): pressedAt
            }
        }

        var capture: (any Capturing)? {
            if case .capturing(_, let capture, _) = self { return capture }
            return nil
        }
    }

    private var phase: Phase = .idle
    private var nextAttemptID = 0

    /// **The generation rule, stated once**. Every callback a bring-up can produce — the
    /// built capture, an inferred denial, the master's creation, a self-end, the wedge timeout —
    /// comes through here first, and one belonging to an attempt that is no longer live is dropped.
    private func isLive(_ attempt: Attempt) -> Bool {
        phase.attempt == attempt
    }

    private func beginAttempt() -> Attempt {
        nextAttemptID += 1
        return Attempt(id: nextAttemptID)
    }

    // MARK: - What the shell and the views read

    /// Armed and capturing (from the press, through the armed-waiting window, to stop). What the
    /// status item keys its recording state off. Derived from the phase, so it cannot drift from it.
    var isRecording: Bool { phase.attempt != nil }

    /// Monotonic uptime of the current record press, or nil at rest. The shell turns it into
    /// `sincePress` for the row's ~500 ms in-flight grace (`RowRecordGlyph`) — the run does not,
    /// because that would mean reading a clock.
    var pressedAt: TimeInterval? { phase.pressedAt }

    /// The Source being captured, for the status item's tooltip and the panel's row state.
    private(set) var recordingSourceID: String?

    /// Master duration in seconds, read off the capture's frame count on the clock's cadence — so
    /// it sits at 0 (menu bar `00:00`) until the first sound.
    private(set) var elapsed: TimeInterval = 0

    /// What the master weighs **right now**, on the same 4 Hz cadence as `elapsed`. The
    /// editor's `Master` row reads this rather than stat'ing the file from its own body: a bare
    /// `stat` is not observable, so the row used to discard a read of `elapsed` purely to invalidate
    /// itself around one.
    private(set) var masterByteCount: Int64?

    /// The active Recording's live meter fill (0...1), sampled off the capture's published peak at
    /// ~20 Hz through `LevelMeter`. A dead tap reads exactly 0, so a soft-faulted
    /// Recording shows a flat meter. 0 at rest.
    private(set) var currentLevel: Double = 0

    /// A short rolling window of recent meter fills, oldest first, that the recording row draws as
    /// a live waveform. All zeros at rest and reset at each start, so a new Recording never inherits
    /// the last one's tail.
    private(set) var meterColumns: [Double] = Array(repeating: 0, count: CaptureRun.meterColumnCount)
    static let meterColumnCount = 48

    /// True once a Recording has actually captured audio this launch. It gates the wedge timeout:
    /// the first bring-up is cancellable-not-timed so a ~90 s TCC prompt cannot abort it, and only
    /// after a success does a slow bring-up become a wedge worth timing out. A
    /// fact about *capture*, held in memory only — nothing about permission is ever persisted.
    private(set) var hasCompletedACapture = false

    /// Set when a denied System Audio Recording grant is inferred; drives the panel's
    /// recovery banner. Cleared on the next record press — retry is simply pressing record again.
    private(set) var permissionRecovery = false

    /// The menu bar's disk tier: amber at 3 hours of Runway, whole item, no glyph.
    /// Driven by the 5 s guard poll while recording; nominal at rest.
    private(set) var runwayTier: RunwayGuard.Tier = .nominal

    /// Set when a record press is refused below the 2 GB floor; drives the panel's one
    /// blocking-message surface, sharing it with `permissionRecovery` — the panel carries at most
    /// one blocking reason at a time. Cleared on the next successful start, and by a denial taking
    /// the surface. Its action opens Finder at the Library.
    private(set) var startBlocker: DiskGuardBlocker?

    /// The Library file currently being written, once the first sound has created it. The editor
    /// refuses to export this one: its `.caf` is still growing in place and its Trim end is
    /// undefined until Stop. Nil when nothing is capturing, or before the first sound.
    private(set) var capturingURL: URL?

    /// Whether the current Recording has heard its first sound. The master is created at the first
    /// sound, which is exactly when `capturingURL` is set — so this reuses that signal.
    var hasFirstSound: Bool { capturingURL != nil }

    /// Whether `recording` is the one being captured right now, and so not exportable.
    func isCapturing(_ recording: Recording) -> Bool {
        isRecording && capturingURL == recording.url
    }

    /// `01:23`, or `1:02:03` past the hour. Frozen at `00:00` through the armed window.
    var elapsedText: String {
        let total = Int(elapsed)
        let (hours, minutes, seconds) = (total / 3600, (total % 3600) / 60, total % 60)
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)
    }

    // MARK: - Cadences

    /// The wedge timeout that applies to bring-up *after* the first successful capture, when the
    /// TCC prompt can no longer appear and a slow start is a hang, not a human reading.
    static let wedgeTimeout: TimeInterval = 10

    /// The menu bar's clock cadence. Not the tick rate: the meter wants 20 Hz and the menu bar
    /// observes `elapsed`, so publishing the clock at the meter's rate would quintuple status-item
    /// churn for no readable gain. This separation is why there used to be two timers.
    static let clockInterval: TimeInterval = 0.25

    /// The disk guard's poll — one `statfs` through the probe, off the realtime IOProc
    /// and the writer thread.
    static let runwayPollInterval: TimeInterval = 5

    private var lastFiguresPublishedAt: TimeInterval?
    private var lastRunwayPollAt: TimeInterval?

    /// The Runway tier/warning reducer for the current Recording, reset at each start so hysteresis
    /// never carries across Recordings.
    private var runwayGuard = RunwayGuard()

    // MARK: - The world, accepted

    private let builder: any CaptureBuilding
    private let runway: any RunwayProbing
    private let reporter: any CaptureReporting
    /// The one module that reads a Recording's facts off the disk. The run holds it for
    /// exactly one read — the growing master's length, below — which is the only file the run has
    /// any business asking about.
    private let reader: any RecordingReading

    init(builder: any CaptureBuilding, runway: any RunwayProbing, reporter: any CaptureReporting,
         reader: any RecordingReading) {
        self.builder = builder
        self.runway = runway
        self.reporter = reporter
        self.reader = reader
    }

    // MARK: - Starting

    /// Begins capturing a Source. Flips to the recording state at once so the menu bar responds to
    /// the press, then asks the builder for a capture — which blocks and can raise the TCC prompt,
    /// so it happens off the main thread and lands back here as a callback.
    func start(_ source: Source, now: TimeInterval) {
        guard !isRecording, !source.processObjectIDs.isEmpty else { return }

        // The start policy against the disk. The rate is a pre-tap estimate — no tap
        // exists yet to report its real format — corrected by the first real poll a few seconds
        let free = runway.freeBytesForLibraryVolume()
        let startDecision = free.map {
            RunwayGuard.startDecision(freeBytes: $0, ratePerSecond: RunwayGuard.nominalRatePerSecond)
        }

        // Refuse below the floor: beginning a Recording the guard kills within a minute leaves junk
        // in the Library and teaches nothing. The refusal raises the panel's one blocking-message
        // surface, whose action opens Finder at the Library.
        if startDecision == .refuse, let free {
            startBlocker = DiskGuardBlocker(freeBytes: free)
            permissionRecovery = false
            return
        }

        startBlocker = nil
        permissionRecovery = false   // retry clears the last denial's banner
        recordingSourceID = source.bundleID
        elapsed = 0
        masterByteCount = nil
        lastFiguresPublishedAt = nil
        lastRunwayPollAt = nil
        resetMeter()

        let attempt = beginAttempt()
        phase = .bringingUp(attempt, pressedAt: now)

        // Begin amber if already inside the 3-hour tier, so a Recording the guard would paint amber
        // within seconds does not flash green first. The first real poll re-decides with
        // the tap's own byte rate, so an off estimate only ever costs a brief wrong colour.
        let amberStart = startDecision == .allowAmber
        runwayGuard = RunwayGuard(tier: amberStart ? .amber : .nominal)
        runwayTier = amberStart ? .amber : .nominal

        // Every hook carries the attempt it was made for, and every one of them lands on the single
        // guard above. The denial hook in particular must not depend on the capture having been
        // attached: the writer thread can infer denial before this callback arrives under load.
        let hooks = CaptureHooks(
            onDenialInferred: { [weak self] in self?.handleDenial(attempt) },
            onMasterCreated: { [weak self] url in self?.masterCreated(url, attempt) },
            onEnded: { [weak self] reason in self?.captureEndedItself(reason, attempt) })

        builder.build(source: source, hooks: hooks) { [weak self] capture in
            guard let self else {
                capture?.stop { _ in }
                return
            }
            if let capture {
                self.attach(capture, attempt)
            } else {
                self.abandon(attempt)
            }
        }
    }

    /// The capture arrived. The attempt may have ended during the (usually brief, but on the first
    /// run possibly ~90 s) build — a second-click cancel, a wedge timeout, or a whole new attempt.
    /// If the world has moved on, this capture is orphaned: tear it down rather than leave a tap
    /// running.
    private func attach(_ capture: any Capturing, _ attempt: Attempt) {
        guard isLive(attempt), let pressedAt = phase.pressedAt else {
            capture.stop { _ in }
            return
        }
        phase = .capturing(attempt, capture, pressedAt: pressedAt)
        // The first clock publish and the first Runway poll both happen on the next tick, within
        // 50 ms — soon enough that the guard's pre-seeded amber is corrected by the tap's real byte
        // rate before anyone reads it.
        lastFiguresPublishedAt = nil
        lastRunwayPollAt = nil
    }

    /// Learn the growing master's path when the first sound creates it, so the editor can refuse to
    /// export the still-capturing Recording.
    private func masterCreated(_ url: URL, _ attempt: Attempt) {
        guard isLive(attempt) else { return }
        capturingURL = url
    }

    // MARK: - Ending

    /// The user pressed stop — one of the two *requested* ends. The editor opens on the
    /// Recording just made, once finalized, but only if there was one: arm-then-never-play opens
    /// nothing.
    func stop() {
        guard let attempt = phase.attempt else { return }
        finalize(reason: .userStopped, attempt)
    }

    /// An end arriving from outside the run: system sleep, or fast user switching folded into it
    ///. Ends the Recording **on the notification**, while the machine is still awake, so
    /// the file is finalized at its last real sample and there is no gap to reconcile — no Dropout.
    func end(_ reason: RecordingEndReason) {
        guard let attempt = phase.attempt else { return }
        finalize(reason: reason, attempt)
    }

    /// App quit or logout: finalize and save unwarned, as accepts for a left-click. A
    /// requested end — no notification, no window. Unlike the other ends this finalizes
    /// **synchronously**, because the process is about to exit: the writer must finish draining,
    /// close the CAF, and write the Dropouts xattr before `applicationWillTerminate` returns. The CAF
    /// is crash-safe even if the OS kills us first, but a synchronous close also secures
    /// the Dropout mark and the tail.
    func endForQuit() {
        guard isRecording else { return }
        let capture = phase.capture
        returnToIdle()
        _ = capture?.stopNow()
    }

    /// The Recording ended itself — recovery exhausted, a format mismatch, or a >30 s gap: one of
    /// the four unrequested ends. The capture has already finalized the file; reclaim it
    /// and tell the user why.
    private func captureEndedItself(_ reason: RecordingEndReason, _ attempt: Attempt) {
        guard isLive(attempt) else { return }
        finalize(reason: reason, attempt)
    }

    /// The one finalization path every end funnels through. Returns to idle at once,
    /// then tears the capture down — off the main thread, since draining the ring and closing the
    /// file may block.
    private func finalize(reason: RecordingEndReason, _ attempt: Attempt) {
        guard isLive(attempt) else { return }
        let capture = phase.capture
        returnToIdle()

        // The capture may still be building (a second click abandoned the attempt mid-bring-up):
        // `attach` will orphan-stop it, and the fresh attempt makes that certain. Only finalize one
        // we actually hold.
        guard let capture else { return }
        capture.stop { [weak self] outcome in
            self?.didFinalize(outcome, requested: reason)
        }
    }

    /// Back with the finalized file (or nil for arm-then-never-play). Tells the user what happened
    /// per the end's kind (/0010).
    private func didFinalize(_ outcome: CaptureOutcome, requested: RecordingEndReason) {
        // A Recording that captured audio — even one a fault ended — means the grant is known good,
        // so a later slow bring-up is a wedge to time out rather than a human at the prompt.
        if outcome.result != nil { hasCompletedACapture = true }
        guard let result = outcome.result else { return }   // nothing saved, nothing to tell.

        // If the capture had already ended itself on a fault, its own reason wins over the caller's.
        switch outcome.selfEndReason ?? requested {
        case .userStopped:
            // The first *completed* Recording is where notification authorization is requested, so a
            // later unrequested end has a channel — never stacked onto a failure.
            reporter.requestNotificationAuthorizationOnce()
            reporter.openEditor(selecting: result.url)
        case .quit:
            break   // you asked for it; the app is leaving. No window, no notification.
        case .diskGuard, .recoveryExhausted, .formatMismatch, .sleep:
            // Name the reason and open the editor on the click — or directly, if auth is absent.
            reporter.report(end: outcome.selfEndReason ?? requested, recordingURL: result.url)
        }
    }

    /// A denied grant was inferred: end the Recording, discard the capture (which removes
    /// any all-zero file), and raise the panel's recovery banner. No file is opened — unlike a
    /// fault-stopped Recording, a denial produced no first sound and so no Recording.
    private func handleDenial(_ attempt: Attempt) {
        guard isLive(attempt) else { return }
        let capture = phase.capture
        returnToIdle()
        capture?.discard()
        startBlocker = nil   // the panel carries at most one blocking reason
        permissionRecovery = true
    }

    /// Bring-up was abandoned before it produced a capture — a build error, or the wedge timeout
    /// firing after the first capture. Return cleanly to idle; any capture the blocked call later
    /// hands back belongs to a stale attempt and tears itself down.
    private func abandon(_ attempt: Attempt) {
        guard isLive(attempt) else { return }
        returnToIdle()
    }

    /// The common return to idle. Everything the generation counter used to guard is carried by the
    /// phase going to `.idle`, which no in-flight attempt can match.
    private func returnToIdle() {
        phase = .idle
        recordingSourceID = nil
        capturingURL = nil
        runwayTier = .nominal
        elapsed = 0
        masterByteCount = nil
        lastFiguresPublishedAt = nil
        lastRunwayPollAt = nil
        resetMeter()
    }

    // MARK: - The clock

    /// One pass of every cadence the run has, over one `now`. The shell ticks at the meter's rate
    /// and each slower cadence gates itself on elapsed time, so a thirty-minute Recording is a
    /// `for` loop in a test rather than thirty minutes of `RunLoop`.
    func tick(now: TimeInterval) {
        switch phase {
        case .idle:
            return
        case .bringingUp(let attempt, let pressedAt):
            // The wedge: armed only *after* the first successful capture. On the first
            // Recording, bring-up is cancellable-not-timed, so it can block ~90 s behind the TCC
            // prompt without aborting; a second click is the only way out then (/0010).
            if hasCompletedACapture, now - pressedAt >= Self.wedgeTimeout { abandon(attempt) }
        case .capturing(_, let capture, _):
            sampleLevel(from: capture)
            publishFigures(from: capture, now: now)
            pollRunway(capture, now: now)
        }
    }

    /// The two figures a capture publishes about itself, at 4 Hz rather than the tick's 20 — see
    /// `clockInterval`. One gate for both, because the reason is the same twice over: the menu bar
    /// observes `elapsed`, and a byte count ticking twenty times a second is ambient motion rather
    /// than a fact changing, which forbids.
    private func publishFigures(from capture: any Capturing, now: TimeInterval) {
        if let last = lastFiguresPublishedAt, now - last < Self.clockInterval { return }
        lastFiguresPublishedAt = now
        elapsed = capture.elapsed
        masterByteCount = capturingURL.flatMap { reader.byteCount(of: $0) }
    }

    /// One meter sample: fold the capture's published peak through `LevelMeter` and roll it into the
    /// window. A dead tap reads exactly 0 (LevelMeter), so a soft-faulted Recording flattens the
    /// meter rather than freezing it at its last live value.
    private func sampleLevel(from capture: any Capturing) {
        let fill = LevelMeter.fill(forLinearPeak: capture.currentLevel)
        currentLevel = fill
        var columns = meterColumns
        columns.removeFirst()
        columns.append(fill)
        meterColumns = columns
    }

    /// Flatten the meter — at each start (so no tail carries over) and at every return to idle.
    private func resetMeter() {
        currentLevel = 0
        meterColumns = Array(repeating: 0, count: Self.meterColumnCount)
    }

    /// One Runway reading: fold current free space and the master's byte rate into the
    /// guard, then act — paint amber, post the 30-minute warning once, or end at the floor. A volume
    /// that cannot be stat'd is skipped, never treated as empty, so an unverifiable disk never ends
    /// a Recording.
    private func pollRunway(_ capture: any Capturing, now: TimeInterval) {
        if let last = lastRunwayPollAt, now - last < Self.runwayPollInterval { return }
        lastRunwayPollAt = now
        guard let free = runway.freeBytesForLibraryVolume() else { return }
        let decision = runwayGuard.receive(freeBytes: free, ratePerSecond: capture.bytesPerSecond)
        runwayTier = decision.tier
        if decision.shouldWarn { reporter.reportRunwayLow() }
        if decision.shouldEnd, let attempt = phase.attempt {
            finalize(reason: .diskGuard, attempt)
        }
    }
}
