import Foundation

// MARK: - Values crossing the boundary

/// What a finalized capture hands back: the file, if a Recording was made at all — nil is the
/// arm-then-never-play case, where the Source never made a sound and nothing was saved — and the
/// reason the Recording ended itself, which wins over the caller's.
nonisolated struct CaptureOutcome: Sendable {
    var result: CaptureResult?
    var selfEndReason: RecordingEndReason?
}

/// The three callbacks a capture makes while it runs, handed over at bring-up so they are set
/// before the writer thread starts — a denial inferred before the capture is attached is still
/// delivered.
nonisolated struct CaptureHooks: Sendable {
    /// A denied System Audio Recording grant was inferred.
    var onDenialInferred: @Sendable @MainActor () -> Void
    /// The master file was created at the first sound, so the editor can learn which
    /// Library file is growing and refuse to export it.
    var onMasterCreated: @Sendable @MainActor (URL) -> Void
    /// The Recording ended itself — one of the four unrequested ends.
    var onEnded: @Sendable @MainActor (RecordingEndReason) -> Void
}

// MARK: - The interfaces

/// One live capture, as the run sees it. The realtime IOProc, the writer thread and the CAF are all
/// below this line; above it there is a duration, a peak, a byte rate and three ways to end.
@MainActor
protocol Capturing: AnyObject {
    /// Master duration in seconds. Sits at 0 through the armed window, so the menu bar reads
    /// `00:00` until the first sound.
    var elapsed: TimeInterval { get }
    /// The most recent chunk's linear peak, for the live meter. A dead tap reads exactly 0, so
    /// a soft-faulted Recording flattens the meter rather than freezing it.
    var currentLevel: Float { get }
    /// The master's on-disk byte rate: the divisor in the Runway's `(free − 2 GB) ÷ rate`.
    var bytesPerSecond: Double { get }
    /// Stop, drain the tail, close the file and write the Dropout mark — off the main thread,
    /// because all of that may block — then hand the outcome back on the main actor.
    func stop(then: @escaping @Sendable @MainActor (CaptureOutcome) -> Void)
    /// Stop and finalize on this thread.
    func stopNow() -> CaptureResult?
    /// Tear down and remove any file outright — the denial path.
    func discard()
}

/// Brings a capture up for one Source. Blocking is the point: tap creation can sit ~90 s behind the
/// TCC prompt, so production builds off the main thread and calls back on the main actor.
@MainActor
protocol CaptureBuilding {
    func build(source: Source, hooks: CaptureHooks,
               then: @escaping @Sendable @MainActor ((any Capturing)?) -> Void)
}

/// The Runway's one input. Nil means *cannot verify*, never *no space* — an unverifiable
/// volume neither refuses a press nor ends a Recording.
@MainActor
protocol RunwayProbing {
    func freeBytesForLibraryVolume() -> Int64?
}

/// Everything the run says to the world when a Recording ends.
@MainActor
protocol CaptureReporting {
    /// Requested at the end of the first *completed* Recording, so a later unrequested end has a
    /// channel — never stacked onto a failure.
    func requestNotificationAuthorizationOnce()
    /// Name an unrequested end and, on the click, open the editor on that Recording.
    func report(end reason: RecordingEndReason, recordingURL: URL)
    /// The 30-minute Runway warning, posted once.
    func reportRunwayLow()
    /// Open the editor directly — the user stop's own ending.
    func openEditor(selecting url: URL)
}

// MARK: - The production adapters

/// `CaptureEngine` behind `Capturing`: this is the one place that knows the engine's teardown
/// blocks and so belongs off the main thread.
@MainActor
final class CoreAudioCapture: Capturing {
    private var engine: CaptureEngine?

    init(engine: CaptureEngine) { self.engine = engine }

    var elapsed: TimeInterval { engine?.elapsed ?? 0 }
    var currentLevel: Float { engine?.currentLevel ?? 0 }
    var bytesPerSecond: Double { engine?.bytesPerSecond ?? 0 }

    func stop(then: @escaping @Sendable @MainActor (CaptureOutcome) -> Void) {
        guard let engine else { then(CaptureOutcome()); return }
        self.engine = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let result = engine.stop()
            // The engine's own reason, read after `stop` has joined the writer thread.
            let outcome = CaptureOutcome(result: result, selfEndReason: engine.endReason)
            Task { @MainActor in then(outcome) }
        }
    }

    func stopNow() -> CaptureResult? {
        guard let engine else { return nil }
        self.engine = nil
        return engine.stop()
    }

    func discard() {
        guard let engine else { return }
        self.engine = nil
        DispatchQueue.global(qos: .userInitiated).async { engine.discard() }
    }
}

/// Builds a `CaptureEngine` off the main thread — tap creation blocks and can raise the TCC prompt
/// — and hands it back wrapped, on the main actor.
@MainActor
struct CoreAudioCaptureBuilder: CaptureBuilding {
    func build(source: Source, hooks: CaptureHooks,
               then: @escaping @Sendable @MainActor ((any Capturing)?) -> Void) {
        let ids = source.processObjectIDs
        let name = source.name
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // The hop lives here, not in the run.
                let engine = try CaptureEngine(
                    processObjectIDs: ids, sourceName: name,
                    onDenialInferred: { Task { @MainActor in hooks.onDenialInferred() } },
                    onMasterCreated: { url in Task { @MainActor in hooks.onMasterCreated(url) } },
                    onEnded: { reason in Task { @MainActor in hooks.onEnded(reason) } })
                Task { @MainActor in then(CoreAudioCapture(engine: engine)) }
            } catch {
                Task { @MainActor in then(nil) }
            }
        }
    }
}

/// The Library volume's free space, resolving symlinks.
@MainActor
struct LibraryVolumeProbe: RunwayProbing {
    func freeBytesForLibraryVolume() -> Int64? { DiskSpace.freeBytesForLibraryVolume() }
}

/// The notification channel and the editor window — the only place `FaultNotifier` and
/// `EditorPresenter` are named on the capture path.
@MainActor
struct SystemCaptureReporter: CaptureReporting {
    func requestNotificationAuthorizationOnce() { FaultNotifier.requestAuthorizationOnce() }

    func report(end reason: RecordingEndReason, recordingURL: URL) {
        FaultNotifier.recordingEnded(reason: reason, recordingURL: recordingURL)
    }

    func reportRunwayLow() { FaultNotifier.runwayLow() }

    func openEditor(selecting url: URL) { EditorPresenter.shared.open(selecting: url) }
}
