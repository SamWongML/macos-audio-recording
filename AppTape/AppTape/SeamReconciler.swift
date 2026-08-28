//
//  SeamReconciler.swift
//  AppTape
//

import Foundation

/// The writer thread's host-time→master reconciler: a pure value reducer, like `CaptureReducer`,
/// so the whole rule is visible to a test off the realtime thread (ADR-0010).
///
/// The master is wall-clock true **by construction rather than by remembering to handle each
/// fault**. Every chunk carries the host time of its first frame; the reducer holds an anchor —
/// the host time at which the master's t=0 landed — and before writing each chunk it compares
/// where the wall clock says the master should be against how many frames it actually holds. A
/// dropped buffer, a rebuilt tap, a whole class of gaps nobody modelled: each shows up here as the
/// same thing — frames the wall clock accounts for that the master does not — and is padded with
/// silence into a **Seam**.
///
/// Two rules keep it honest (ADR-0010):
/// - **`mHostTime` is trusted only when `hostTimeValid`.** A timestamp without
///   `kAudioTimeStampHostTimeValid` cannot be reconciled against, so the reducer assumes contiguity
///   — a 10 ms slip beats a guess.
/// - **A gap beyond 30 s ends the Recording.** A writer that padded whatever it could not account
///   for would, on wake, write ~12 GB of zeros for an overnight sleep. Thirty seconds is roughly
///   3× the worst legitimate Seam (10 s soft detection + ~1 s rebuild), so it is a backstop, not a
///   load-bearing path — it is the sleep end arriving by another route, not a seventh end.
///
/// The reducer sees only that there was a gap; the **cause** comes from the capture controller
/// knowing whether a rebuild was in flight (ADR-0010).
nonisolated struct SeamReconciler {
    let sampleRate: Double
    /// A gap larger than this ends the Recording rather than being padded.
    let maxGapSeconds: Double
    /// The smallest gap worth padding as a Seam. Below it, sub-frame host-time rounding jitter would
    /// manufacture a one-frame Seam on every chunk; above it sits the smallest real cause, a dropped
    /// 512-frame buffer (~10.67 ms at 48 kHz), so every genuine overrun still registers.
    let minSeamFrames: Int

    /// Frames committed to the master so far — real audio plus every pad. Matches what the writer
    /// has actually written once each decision is applied.
    private(set) var masterFrames: Int = 0
    /// Every Seam padded so far, in order, with `start` at the master frame each began.
    private(set) var seams: [Seam] = []

    /// Host time (seconds) at which the master's t=0 landed, captured from the first chunk that
    /// carries a valid host time. Nil until then — before it, everything is contiguous.
    private var anchorSeconds: Double?

    init(sampleRate: Double, maxGapSeconds: Double = 30, minSeamFrames: Int = 128) {
        self.sampleRate = sampleRate
        self.maxGapSeconds = maxGapSeconds
        self.minSeamFrames = minSeamFrames
    }

    enum Decision: Equatable {
        /// No gap: write the chunk as-is.
        case append
        /// A gap opened: write `frames` zero-frames first — that is the Seam — then the chunk.
        case pad(frames: Int, cause: Seam.Cause)
        /// The gap exceeded 30 s: end the Recording. The chunk is discarded and the master ends at
        /// its last real sample; nothing is padded (ADR-0010).
        case end
    }

    /// Reconcile one chunk against the wall clock, before it is written.
    ///
    /// - Parameters:
    ///   - hostTimeSeconds: the host time of the chunk's first frame, in seconds (a monotonic
    ///     machine clock, converted from `mHostTime`).
    ///   - hostTimeValid: whether the timestamp carried `kAudioTimeStampHostTimeValid`.
    ///   - newFrames: the frames this chunk contributes to the master (after any leading-silence
    ///     skip the `CaptureReducer` already applied).
    ///   - rebuildInFlight: whether the capture controller was rebuilding the tap when this gap
    ///     opened. Its only effect is the Seam's cause.
    mutating func account(hostTimeSeconds: Double,
                          hostTimeValid: Bool,
                          newFrames: Int,
                          rebuildInFlight: Bool) -> Decision {
        precondition(newFrames >= 0, "a chunk cannot contribute negative frames")

        guard let anchor = anchorSeconds else {
            // Establish the anchor on the first chunk that can be trusted; until then, contiguous.
            if hostTimeValid { anchorSeconds = hostTimeSeconds - Double(masterFrames) / sampleRate }
            masterFrames += newFrames
            return .append
        }
        guard hostTimeValid else {
            // Cannot reconcile an untrusted timestamp — assume contiguity.
            masterFrames += newFrames
            return .append
        }

        let expected = Int(((hostTimeSeconds - anchor) * sampleRate).rounded())
        let gap = expected - masterFrames

        if gap > Int((maxGapSeconds * sampleRate).rounded()) {
            return .end
        }
        if gap >= minSeamFrames {
            let cause: Seam.Cause = rebuildInFlight ? .rebuild : .overrun
            seams.append(Seam(start: masterFrames, frames: gap, cause: cause))
            masterFrames += gap          // the pad
            masterFrames += newFrames    // the chunk after it
            return .pad(frames: gap, cause: cause)
        }
        // Gap within tolerance (or the chunk arrived a touch early): just append.
        masterFrames += newFrames
        return .append
    }
}
