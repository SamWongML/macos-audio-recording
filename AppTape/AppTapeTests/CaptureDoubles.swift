//
//  CaptureDoubles.swift
//  AppTapeTests
//

import Foundation
@testable import AppTape

/// The second conformance of each of `CaptureRun`'s four interfaces — the reason they exist.
/// Between them they replace Core Audio, a `statfs`, a notification centre and a window, so a
/// Recording's whole life is a sequence of calls a test makes and reads back.

/// A capture that never touches Core Audio: the test sets what it reports and reads back what was
/// asked of it.
@MainActor
final class FakeCapture: Capturing {
    var elapsed: TimeInterval = 0
    var currentLevel: Float = 0
    /// 48 kHz stereo Float32 — the ADR-0009 worked rate, so Runway arithmetic in a test matches the
    /// arithmetic in `RunwayGuardTests`.
    var bytesPerSecond: Double = 8 * 48_000

    /// What `stop` hands back. The default is arm-then-never-play: no file, no self-end (ADR-0016).
    var outcome = CaptureOutcome()

    private(set) var stopCount = 0
    private(set) var stopNowCount = 0
    private(set) var discardCount = 0

    /// Whether this capture was torn down at all — true for a finalize *and* for an orphan stop,
    /// which are the same call by design: a bring-up that never produced a first sound left no file,
    /// so there is nothing for the orphan path to remove.
    var wasTornDown: Bool { stopCount + stopNowCount + discardCount > 0 }

    func stop(then: @escaping @Sendable @MainActor (CaptureOutcome) -> Void) {
        stopCount += 1
        then(outcome)
    }

    func stopNow() -> CaptureResult? {
        stopNowCount += 1
        return outcome.result
    }

    func discard() { discardCount += 1 }
}

/// Bring-up under the test's control. The three things it can do are the three things a real
/// bring-up does: hand a capture back, throw, or block — and the third one, `stall`, is the only
/// way ADR-0010's wedge and its three races can be written down at all.
@MainActor
final class FakeCaptureBuilder: CaptureBuilding {
    private(set) var builds: [(source: Source, hooks: CaptureHooks)] = []

    /// One outstanding completion **per bring-up**, not one in total. That is the whole point: a
    /// blocked first attempt has to be able to return *after* a second press, which is the race
    /// ADR-0010's generation rule exists for and the one a single slot cannot express.
    private var pending: [(@Sendable @MainActor ((any Capturing)?) -> Void)?] = []

    var buildCount: Int { builds.count }

    /// The hooks of one bring-up — how a test plays the writer thread's part, in a straight line.
    func hooks(forBuild index: Int = 0) -> CaptureHooks { builds[index].hooks }

    /// Whether that bring-up is still outstanding: the blocked call, not yet returned.
    func isBuilding(_ index: Int = 0) -> Bool { pending.indices.contains(index) && pending[index] != nil }

    func build(source: Source, hooks: CaptureHooks,
               then: @escaping @Sendable @MainActor ((any Capturing)?) -> Void) {
        builds.append((source, hooks))
        pending.append(then)
    }

    /// The ordinary bring-up: hand a capture back now. Defaults to the most recent one, and to a
    /// fresh capture — built here rather than as a default argument, which is evaluated in a
    /// nonisolated context where a main-actor initializer cannot be called.
    @discardableResult
    func finish(build index: Int? = nil, with capture: FakeCapture? = nil) -> FakeCapture {
        let capture = capture ?? FakeCapture()
        let i = index ?? pending.count - 1
        let then = pending[i]
        pending[i] = nil
        then?(capture)
        return capture
    }

    /// The bring-up threw — `ProcessTap` could not build a tap.
    func fail(build index: Int? = nil) {
        let i = index ?? pending.count - 1
        let then = pending[i]
        pending[i] = nil
        then?(nil)
    }
}

/// A settable free-space reading, `nil` included — the volume that cannot be stat'd, which must
/// never be read as "no space" (ADR-0009).
@MainActor
final class StubRunway: RunwayProbing {
    var freeBytes: Int64?
    private(set) var pollCount = 0

    init(freeBytes: Int64?) { self.freeBytes = freeBytes }

    func freeBytesForLibraryVolume() -> Int64? {
        pollCount += 1
        return freeBytes
    }
}

/// Everything the run said, in order. Assertions read this array instead of watching a notification
/// centre and an editor window the suite cannot drive.
@MainActor
final class TellingLog: RunTelling {
    enum Told: Equatable {
        case authorizationRequested
        case end(RecordingEndReason, URL)
        case runwayLow
        case editorOpened(URL)
    }

    private(set) var told: [Told] = []

    func requestNotificationAuthorizationOnce() { told.append(.authorizationRequested) }

    func tell(end reason: RecordingEndReason, recordingURL: URL) {
        told.append(.end(reason, recordingURL))
    }

    func tellRunwayLow() { told.append(.runwayLow) }

    func openEditor(selecting url: URL) { told.append(.editorOpened(url)) }
}
