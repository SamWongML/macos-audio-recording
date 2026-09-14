import AppKit
import Observation

/// The shell around one `CaptureRun`: the record presses, the lifecycle notifications, the one
/// timer that gives the run its sense of time, and the observation the menu bar and the panel
/// render.
@MainActor
@Observable
final class RecordingController {
    static let shared = RecordingController()

    /// The run itself. Held rather than hidden, so a test or a preview can build a controller over
    /// a run with doubles in it.
    let run: CaptureRun

    /// The production wiring: a real Core Audio capture, a real `statfs`, a real notification
    /// centre, the real editor window and the real file system.
    init() {
        self.run = CaptureRun(builder: CoreAudioCaptureBuilder(),
                              runway: LibraryVolumeProbe(),
                              reporter: SystemCaptureReporter(),
                              reader: RecordingReader())
    }

    /// For a test or a preview: a controller over a run with doubles in it.
    init(run: CaptureRun) {
        self.run = run
    }

    /// Seconds since the current record press, or nil at rest — `RowRecordGlyph`'s grace input.
    var sincePress: TimeInterval? {
        run.pressedAt.map { ProcessInfo.processInfo.systemUptime - $0 }
    }

    // MARK: - The presses

    func start(_ source: Source) {
        run.start(source, now: uptime)
        // A press refused below the disk floor never enters a recording state, so there is nothing
        // to clock.
        if run.isRecording { startClock() }
    }

    func stop() { run.stop() }

    /// System sleep or fast user switching, folded together.
    func endForSleep() { run.end(.sleep) }

    /// App quit or logout. Finalizes synchronously — the process is about to exit.
    func endForQuit() {
        run.endForQuit()
        stopClock()
    }

    /// Registers the lifecycle ends that arrive as notifications: sleep, fast user switching, and
    /// logout/power-off.
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

    /// 20 Hz — the meter's cadence, and the fastest thing the run does.
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
