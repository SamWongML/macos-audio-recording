//
//  CaptureAdapters.swift
//  AppTape
//

import Foundation

/// The seam between `CaptureRun` — which owns ADR-0007's six ends, ADR-0008's denial inference,
/// ADR-0009's Runway guard and ADR-0010's generation rule — and the world those decisions are made
/// against: Core Audio, the file system, the notification centre and the editor window.
///
/// Four interfaces, and exactly two conformances each: the production adapter in this file and the
/// double in `AppTapeTests/CaptureDoubles.swift`. That is the bar an interface here has to clear.
/// None of them carries a decision; each is a forwarding shell, so the whole of the policy stays in
/// one testable place and the untestable parts stay this thin.

// MARK: - Values crossing the seam

/// What a finalized capture hands back: the file, if a Recording was made at all — nil is the
/// arm-then-never-play case, where the Source never made a sound and nothing was saved (ADR-0016) —
/// and the reason the Recording ended **itself**, which wins over the caller's (ADR-0007).
nonisolated struct CaptureOutcome: Sendable {
    var result: CaptureResult?
    var selfEndReason: RecordingEndReason?
}

/// The three callbacks a capture makes while it runs, handed over at bring-up so they are set
/// before the writer thread starts — a denial inferred before the capture is attached is still
/// delivered.
///
/// They are **main-actor calls, not hops**: the run does not know that the writer thread is a
/// different thread, and the adapter that does owns the hop, exactly as it owns the teardown
/// dispatch. That is also what lets a test play the writer thread's part in a straight line.
nonisolated struct CaptureHooks: Sendable {
    /// A denied System Audio Recording grant was inferred (ADR-0008).
    var onDenialInferred: @Sendable @MainActor () -> Void
    /// The master file was created at the first sound (ADR-0016), so the editor can learn which
    /// Library file is growing and refuse to export it (ADR-0012).
    var onMasterCreated: @Sendable @MainActor (URL) -> Void
    /// The Recording ended itself — one of the four unrequested ends (ADR-0010).
    var onEnded: @Sendable @MainActor (RecordingEndReason) -> Void
}

// MARK: - The interfaces

/// One live capture, as the run sees it. The realtime IOProc, the writer thread and the CAF are all
/// below this line; above it there is a duration, a peak, a byte rate and three ways to end.
@MainActor
protocol Capturing: AnyObject {
    /// Master duration in seconds. Sits at 0 through the armed window, so the menu bar reads
    /// `00:00` until the first sound (ADR-0016).
    var elapsed: TimeInterval { get }
    /// The most recent chunk's linear peak, for the live meter. A dead tap reads **exactly 0**, so
    /// a soft-faulted Recording flattens the meter rather than freezing it (issue #59).
    var currentLevel: Float { get }
    /// The master's on-disk byte rate — the divisor in the Runway's `(free − 2 GB) ÷ rate`
    /// (ADR-0009). Not a constant across Recordings, which is why the guard takes it as an input.
    var bytesPerSecond: Double { get }
    /// Stop, drain the tail, close the file and write the Seam mark — **off the main thread**,
    /// because all of that may block (ADR-0003) — then hand the outcome back on the main actor.
    /// Also the orphan teardown: a capture the world has moved past is stopped, not discarded,
    /// because a bring-up that never produced a first sound left no file to remove.
    func stop(then: @escaping @Sendable @MainActor (CaptureOutcome) -> Void)
    /// Stop and finalize **on this thread**. The quit path only: the process is about to exit, so
    /// the writer must finish draining, close the CAF and write the Seams xattr before
    /// `applicationWillTerminate` returns (ADR-0003).
    func stopNow() -> CaptureResult?
    /// Tear down and **remove** any file outright — the denial path (ADR-0008). A Recording that
    /// never held a non-zero sample is not a Recording, and putting pure silence in the Trash asks
    /// the user a question about something they never made.
    func discard()
}

/// Brings a capture up for one Source. Blocking is the point: tap creation can sit ~90 s behind the
/// TCC prompt (ADR-0008), so production builds off the main thread and calls back on the main actor.
///
/// The callback's three shapes are the three things bring-up can do, and the suite needs all three:
/// a capture (it worked), nil (it threw — the run abandons the attempt), and **no callback at all**,
/// which is the wedge ADR-0010's timeout exists for.
@MainActor
protocol CaptureBuilding {
    func build(source: Source, hooks: CaptureHooks,
               then: @escaping @Sendable @MainActor ((any Capturing)?) -> Void)
}

/// The Runway's one input (ADR-0009). Nil means *cannot verify*, never *no space* — an unverifiable
/// volume neither refuses a press nor ends a Recording.
@MainActor
protocol RunwayProbing {
    func freeBytesForLibraryVolume() -> Int64?
}

/// Everything the run says to the world when a Recording ends: the notification channel and the
/// editor window (ADR-0009/0010). One interface, so the suite reads back *what was told* rather
/// than watching a notification centre it cannot drive.
@MainActor
protocol RunTelling {
    /// Requested at the end of the first *completed* Recording, so a later unrequested end has a
    /// channel — never stacked onto a failure (ADR-0009).
    func requestNotificationAuthorizationOnce()
    /// Name an unrequested end and, on the click, open the editor on that Recording (ADR-0010).
    func tell(end reason: RecordingEndReason, recordingURL: URL)
    /// The 30-minute Runway warning, posted once (ADR-0009).
    func tellRunwayLow()
    /// Open the editor directly — the user stop's own ending.
    func openEditor(selecting url: URL)
}

// MARK: - The production adapters

/// `CaptureEngine` behind `Capturing`: this is the one place that knows the engine's teardown
/// blocks and so belongs off the main thread. The engine is released as soon as an end is asked
/// for, so a second end finds nothing to tear down twice.
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
/// (issue #12) — and hands it back wrapped, on the main actor.
@MainActor
struct CoreAudioCaptureBuilder: CaptureBuilding {
    func build(source: Source, hooks: CaptureHooks,
               then: @escaping @Sendable @MainActor ((any Capturing)?) -> Void) {
        let ids = source.processObjectIDs
        let name = source.name
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // The hop lives here, not in the run. The engine calls these from its writer
                // thread; each must not call back synchronously into the engine, which would
                // deadlock that thread against its own finalization.
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

/// The Library volume's free space, resolving symlinks (ADR-0009).
@MainActor
struct LibraryVolumeProbe: RunwayProbing {
    func freeBytesForLibraryVolume() -> Int64? { DiskSpace.freeBytesForLibraryVolume() }
}

/// The notification channel and the editor window — the only place `FaultNotifier` and
/// `EditorPresenter` are named on the capture path.
@MainActor
struct ShellTelling: RunTelling {
    func requestNotificationAuthorizationOnce() { FaultNotifier.requestAuthorizationOnce() }

    func tell(end reason: RecordingEndReason, recordingURL: URL) {
        FaultNotifier.recordingEnded(reason: reason, recordingURL: recordingURL)
    }

    func tellRunwayLow() { FaultNotifier.runwayLow() }

    func openEditor(selecting url: URL) { EditorPresenter.shared.open(selecting: url) }
}
