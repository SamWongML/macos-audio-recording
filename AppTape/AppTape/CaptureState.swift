//
//  CaptureState.swift
//  AppTape
//

import Foundation

/// What the editor is allowed to know about the capture in flight.
///
/// Three reads and one derivation, which is the whole of what the editor's five views ask: the
/// transport, the brief, the sidebar row, the lane and the Export dock. **Read-only by
/// construction** — `start` and `stop` belong to the panel and the status item, which hold the shell
/// itself (ADR-0004) — so the editor cannot command capture by reaching for a member it was handed
/// for another purpose.
///
/// A noun where this repo's other five protocols are gerunds (`Capturing`, `CaptureBuilding`,
/// `RunwayProbing`, `RunTelling`, `RecordingReading`). Those are *doing* interfaces: something acts
/// on the run's behalf. This one is a reading, in the other direction, so a gerund would misname it —
/// and `CaptureReading` would sit one letter from `RecordingReading`, which means *reads a
/// Recording's facts off disk* and is a different thing entirely.
///
/// Exactly two conformances, the bar `CaptureAdapters.swift` sets: `CaptureRun` in the app, and
/// `PreviewCapture` for the capture states the real app can only reach through Core Audio, a live tap
/// and a Source making noise.
///
/// `@MainActor` is the app target's default (ADR-0022) and is right here rather than incidental:
/// every member is read from a view body.
@MainActor
protocol CaptureState {
    /// Master duration so far, published on the run's 4 Hz clock gate — 0 through the armed window
    /// before the first sound (ADR-0016). The sidebar row's live clock and the transport's readout.
    var elapsed: TimeInterval { get }

    /// What the master weighs **right now**, on the same 4 Hz gate (ADR-0031, ADR-0044). Nil through
    /// the armed window and at rest; a file merely *arriving* in the Library is not the one being
    /// captured and has no figure to be current about.
    var masterByteCount: Int64? { get }

    /// Whether `recording` is the one being captured right now, and so not exportable: its `.caf` is
    /// still growing in place and its Trim end is undefined until Stop (ADR-0012).
    func isCapturing(_ recording: Recording) -> Bool
}

extension CaptureState {
    /// Whether this Recording's audio is **still arriving**: it has no frames at all, or it is the
    /// one being captured right now. Either way the editor is holding a reading of a file that is
    /// still being written (ADR-0021), so the lane says so instead of drawing it and the transport
    /// offers no Play.
    ///
    /// The two halves are not redundant, which is the whole point. A master is adopted moments after
    /// the first sound creates it, so its `frameCount` is not zero, just tiny — and a Recording that
    /// has captured 51 frames of a two-minute take drew that fraction of a second **stretched across
    /// the entire lane** as a solid slab (issue #80). Zero frames alone did not catch it.
    ///
    /// An extension rather than a requirement, and that is load-bearing: as a requirement, every
    /// conformance would restate the rule with nothing checking that they agreed, and a conformance
    /// that kept a member of this name would be reached by a call on the concrete type while a call
    /// through `any CaptureState` took this one. The rule exists once, here.
    func isStillArriving(_ recording: Recording) -> Bool {
        recording.isEmpty || isCapturing(recording)
    }
}

/// The production conformance. Every member is already there, unchanged — which is the sign the
/// interface was cut where the code was already divided rather than across it.
extension CaptureRun: CaptureState {}
