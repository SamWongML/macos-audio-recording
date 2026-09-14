import Foundation
import Observation

/// One press's attempt at capturing.
nonisolated private struct Attempt: Equatable, Sendable {
    let id: Int
}

/// One run of capture, start to stop: the six ends, the denial inference, the Runway guard and
/// the generation rule all live here.
@MainActor
@Observable
final class CaptureRun {

    // MARK: - Where one attempt is in its life

    /// The run's whole state, as one value.
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

    private func isLive(_ attempt: Attempt) -> Bool {
        phase.attempt == attempt
    }

    private func beginAttempt() -> Attempt {
        nextAttemptID += 1
        return Attempt(id: nextAttemptID)
    }

    // MARK: - What the shell and the views read

    /// Armed and capturing (from the press, through the armed-waiting window, to stop). What the
    /// status item keys its recording state off. Derived from the phase, so it cannot drift.
    var isRecording: Bool { phase.attempt != nil }

    /// Monotonic uptime of the current record press, or nil at rest.
    var pressedAt: TimeInterval? { phase.pressedAt }

    /// The Source being captured, for the status item's tooltip and the panel's row state.
    private(set) var recordingSourceID: String?

    /// Master duration in seconds, read off the capture's frame count on the clock's cadence — so
    /// it sits at 0 (menu bar `00:00`) until the first sound.
    private(set) var elapsed: TimeInterval = 0

    /// What the master weighs right now, on the same 4 Hz cadence as `elapsed`.
    private(set) var masterByteCount: Int64?

    /// The active Recording's live meter fill (0...1), sampled off the capture's published peak at
    /// ~20 Hz through `LevelMeter`.
    private(set) var currentLevel: Double = 0

    /// A short rolling window of recent meter fills, oldest first, that the recording row draws as
    /// a live waveform.
    private(set) var meterColumns: [Double] = Array(repeating: 0, count: CaptureRun.meterColumnCount)
    static let meterColumnCount = 48

    /// True once a Recording has actually captured audio this launch.
    private(set) var hasCompletedACapture = false

    /// Set when a denied System Audio Recording grant is inferred; drives the panel's
    /// recovery banner. Cleared on the next record press — retry is simply pressing record again.
    private(set) var permissionRecovery = false

    /// The menu bar's disk tier: amber at 3 hours of Runway, whole item, no glyph.
    /// Driven by the 5 s guard poll while recording; nominal at rest.
    private(set) var runwayTier: RunwayGuard.Tier = .nominal

    /// Set when a record press is refused below the 2 GB floor; drives the panel's one
    /// blocking-message surface, sharing it with `permissionRecovery` — the panel carries at most
    /// one blocking reason at a time.
    private(set) var startBlocker: DiskGuardBlocker?

    /// The Library file currently being written, once the first sound has created it.
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

    /// The menu bar's clock cadence.
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
    /// The one module that reads a Recording's facts off the disk.
    private let reader: any RecordingReading

    init(
        builder: any CaptureBuilding, runway: any RunwayProbing, reporter: any CaptureReporting,
        reader: any RecordingReading
    ) {
        self.builder = builder
        self.runway = runway
        self.reporter = reporter
        self.reader = reader
    }

    // MARK: - Starting

    func start(_ source: Source, now: TimeInterval) {
        guard !isRecording, !source.processObjectIDs.isEmpty else { return }

        // The start policy against the disk.
        let free = runway.freeBytesForLibraryVolume()
        let startDecision = free.map {
            RunwayGuard.startDecision(freeBytes: $0, ratePerSecond: RunwayGuard.nominalRatePerSecond)
        }

        // Refuse below the floor: beginning a Recording the guard kills within a minute leaves junk
        // in the Library and teaches nothing.
        if startDecision == .refuse, let free {
            startBlocker = DiskGuardBlocker(freeBytes: free)
            permissionRecovery = false
            return
        }

        startBlocker = nil
        permissionRecovery = false  // retry clears the last denial's banner
        recordingSourceID = source.bundleID
        elapsed = 0
        masterByteCount = nil
        lastFiguresPublishedAt = nil
        lastRunwayPollAt = nil
        resetMeter()

        let attempt = beginAttempt()
        phase = .bringingUp(attempt, pressedAt: now)

        // Begin amber if already inside the 3-hour tier, so a Recording the guard would paint amber
        // within seconds does not flash green first.
        let amberStart = startDecision == .allowAmber
        runwayGuard = RunwayGuard(tier: amberStart ? .amber : .nominal)
        runwayTier = amberStart ? .amber : .nominal

        // Every hook carries the attempt it was made for, and every one of them lands on the single
        // guard above.
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

    /// The capture arrived.
    private func attach(_ capture: any Capturing, _ attempt: Attempt) {
        guard isLive(attempt), let pressedAt = phase.pressedAt else {
            capture.stop { _ in }
            return
        }
        phase = .capturing(attempt, capture, pressedAt: pressedAt)
        // The first clock publish and the first Runway poll both happen on the next tick, within 50
        // ms — soon enough that the guard's pre-seeded amber is corrected by the tap's real byte
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

    /// The user pressed stop — one of the two *requested* ends.
    func stop() {
        guard let attempt = phase.attempt else { return }
        finalize(reason: .userStopped, attempt)
    }

    /// An end arriving from outside the run: system sleep, or fast user switching folded into it.
    func end(_ reason: RecordingEndReason) {
        guard let attempt = phase.attempt else { return }
        finalize(reason: reason, attempt)
    }

    /// App quit or logout: finalize and save unwarned.
    func endForQuit() {
        guard isRecording else { return }
        let capture = phase.capture
        returnToIdle()
        _ = capture?.stopNow()
    }

    /// The Recording ended itself — recovery exhausted, a format mismatch, or a >30 s gap: one of
    /// the four unrequested ends.
    private func captureEndedItself(_ reason: RecordingEndReason, _ attempt: Attempt) {
        guard isLive(attempt) else { return }
        finalize(reason: reason, attempt)
    }

    /// The one finalization path every end funnels through.
    private func finalize(reason: RecordingEndReason, _ attempt: Attempt) {
        guard isLive(attempt) else { return }
        let capture = phase.capture
        returnToIdle()

        // The capture may still be building (a second click abandoned the attempt mid-bring-up):
        // `attach` will orphan-stop it, and the fresh attempt makes that certain.
        guard let capture else { return }
        capture.stop { [weak self] outcome in
            self?.didFinalize(outcome, requested: reason)
        }
    }

    /// Back with the finalized file (or nil for arm-then-never-play). Tells the user what happened
    /// per the end's kind.
    private func didFinalize(_ outcome: CaptureOutcome, requested: RecordingEndReason) {
        // A Recording that captured audio — even one a fault ended — means the grant is known
        // good, so a later slow bring-up is a wedge to time out rather than a human at the prompt.
        if outcome.result != nil { hasCompletedACapture = true }
        guard let result = outcome.result else { return }  // nothing saved, nothing to tell.

        // If the capture had already ended itself on a fault, its own reason wins over the caller's.
        switch outcome.selfEndReason ?? requested {
        case .userStopped:
            // The first *completed* Recording is where notification authorization is requested, so
            // a later unrequested end has a channel — never stacked onto a failure.
            reporter.requestNotificationAuthorizationOnce()
            reporter.openEditor(selecting: result.url)
        case .quit:
            break  // you asked for it; the app is leaving. No window, no notification.
        case .diskGuard, .recoveryExhausted, .formatMismatch, .sleep:
            // Name the reason and open the editor on the click — or directly, if auth is absent.
            reporter.report(end: outcome.selfEndReason ?? requested, recordingURL: result.url)
        }
    }

    /// A denied grant was inferred: end the Recording, discard the capture (which removes any
    /// all-zero file), and raise the panel's recovery banner.
    private func handleDenial(_ attempt: Attempt) {
        guard isLive(attempt) else { return }
        let capture = phase.capture
        returnToIdle()
        capture?.discard()
        startBlocker = nil  // the panel carries at most one blocking reason
        permissionRecovery = true
    }

    /// Bring-up was abandoned before it produced a capture — a build error, or the wedge timeout
    /// firing after the first capture.
    private func abandon(_ attempt: Attempt) {
        guard isLive(attempt) else { return }
        returnToIdle()
    }

    /// The common return to idle. The phase going to `.idle` is what no in-flight attempt can
    /// match, so nothing else has to guard it.
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

    /// One pass of every cadence the run has, over one `now`.
    func tick(now: TimeInterval) {
        switch phase {
        case .idle:
            return
        case .bringingUp(let attempt, let pressedAt):
            // The wedge: armed only *after* the first successful capture.
            if hasCompletedACapture, now - pressedAt >= Self.wedgeTimeout { abandon(attempt) }
        case .capturing(_, let capture, _):
            sampleLevel(from: capture)
            publishFigures(from: capture, now: now)
            pollRunway(capture, now: now)
        }
    }

    /// The two figures a capture publishes about itself, at 4 Hz rather than the tick's 20 — see
    /// `clockInterval`.
    private func publishFigures(from capture: any Capturing, now: TimeInterval) {
        if let last = lastFiguresPublishedAt, now - last < Self.clockInterval { return }
        lastFiguresPublishedAt = now
        elapsed = capture.elapsed
        masterByteCount = capturingURL.flatMap { reader.byteCount(of: $0) }
    }

    /// One meter sample: fold the capture's published peak through `LevelMeter` and roll it into
    /// the window.
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

    /// One Runway reading: fold current free space and the master's byte rate into the guard, then
    /// act — paint amber, post the 30-minute warning once, or end at the floor.
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
