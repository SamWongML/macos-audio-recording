//
//  RecordingController.swift
//  AppTape
//

import AppKit
import Observation

/// The shell around one `CaptureRun`: the record presses, the lifecycle notifications, the one
/// timer that gives the run its sense of time, and the observation the menu bar and the panel
/// render.
///
/// Everything that *decides* anything lives in `CaptureRun`, which accepts its world instead of
/// creating it and so can be tested. What is left here is the part that cannot be: `Timer` on the
/// main run loop, `NSWorkspace`'s notifications, and the single `ProcessInfo` clock read those two
/// need. Keep it that way — a decision that lands in this file is a decision nothing verifies.
@MainActor
@Observable
final class RecordingController {
    static let shared = RecordingController()

    /// The run itself. Held rather than hidden, so a test or a preview can build a controller over
    /// a run with doubles in it.
    let run: CaptureRun

    /// The production wiring: a real Core Audio capture, a real `statfs`, a real notification
    /// centre and the real editor window. Written as its own initializer rather than a default
    /// argument because a default argument is evaluated in a nonisolated context, and every one of
    /// these adapters is main-actor isolated.
    init() {
        self.run = CaptureRun(builder: CoreAudioCaptureBuilder(),
                              runway: LibraryVolumeProbe(),
                              telling: ShellTelling())
    }

    /// For a test or a preview: a controller over a run with doubles in it.
    init(run: CaptureRun) {
        self.run = run
    }

    // MARK: - What the views read
    //
    // Forwards, not copies. Observation tracks through a computed property, so a view reading
    // `recorder.isRecording` registers on the run's own stored property and nothing re-renders more
    // often than it did before the run existed.

    var isRecording: Bool { run.isRecording }
    var recordingSourceID: String? { run.recordingSourceID }
    var elapsed: TimeInterval { run.elapsed }
    var elapsedText: String { run.elapsedText }
    var currentLevel: Double { run.currentLevel }
    var meterColumns: [Double] { run.meterColumns }
    var hasFirstSound: Bool { run.hasFirstSound }
    var permissionRecovery: Bool { run.permissionRecovery }
    var runwayTier: RunwayGuard.Tier { run.runwayTier }
    var startRefusal: DiskGuardRefusal? { run.startRefusal }
    var capturingURL: URL? { run.capturingURL }

    /// Seconds since the current record press, or nil at rest — `RowRecordGlyph`'s grace input.
    /// The subtraction happens here because the run reads no clock; it publishes the press time and
    /// this is the one place that asks what time it is now.
    var sincePress: TimeInterval? {
        run.pressedAt.map { ProcessInfo.processInfo.systemUptime - $0 }
    }

    func isCapturing(_ recording: Recording) -> Bool { run.isCapturing(recording) }
    func isStillArriving(_ recording: Recording) -> Bool { run.isStillArriving(recording) }

    // MARK: - The presses

    func start(_ source: Source) {
        run.start(source, now: uptime)
        // A press refused below the disk floor (ADR-0009) never enters a recording state, so there
        // is nothing to clock.
        if run.isRecording { startClock() }
    }

    func stop() { run.stop() }

    /// System sleep or fast user switching, folded together (ADR-0007).
    func endForSleep() { run.end(.sleep) }

    /// App quit or logout. Finalizes synchronously — the process is about to exit (ADR-0003).
    func endForQuit() {
        run.endForQuit()
        stopClock()
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

    // MARK: - The clock

    /// 20 Hz — the meter's cadence, and the fastest thing the run does (issue #59). Every slower
    /// cadence is arithmetic over `now` inside the run: the menu bar's 4 Hz clock, the Runway's 5 s
    /// poll, and the wedge timeout. Four timers used to say this.
    static let tickInterval: TimeInterval = 1.0 / 20.0

    private var clock: Timer?

    private func startClock() {
        guard clock == nil else { return }
        let timer = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.run.tick(now: self.uptime)
                // The run ends itself on a fault, the disk floor, a denial or the wedge, so the
                // clock follows its state rather than being stopped by each end's own path.
                if !self.run.isRecording { self.stopClock() }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        clock = timer
    }

    private func stopClock() {
        clock?.invalidate()
        clock = nil
    }

    /// The only clock read in the capture path.
    private var uptime: TimeInterval { ProcessInfo.processInfo.systemUptime }
}
