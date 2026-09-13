//
//  LevelMeter.swift
//  AppTape
//

import Foundation

/// Maps a tap's raw linear peak amplitude to a normalized meter fill (0...1), on a decibel
/// scale so ordinary speech is visible next to one loud transient (issue #59). The panel's
/// per-row level meter reads the recording tap's current level through this.
///
/// The whole point of the seam is the boundary case: a **dead tap reads exactly zero**. A
/// soft-fault tap that has gone all-zero, a famine with no callbacks at all, or a row with no
/// tap — each hands in `nil` or a non-positive peak, and each reads `0`, never a decaying ghost
/// or a noise-floor smear. Any smoothing belongs to the view's animation, not to the number,
/// so the number stays honest.
/// Explicitly `nonisolated`: the writer thread drives this, and the target's default isolation
/// is `MainActor` (ADR-0022). The annotation is load-bearing — dropping it silently main-actors
/// a piece of the capture spine.
nonisolated enum LevelMeter {
    /// The quietest peak the meter shows above the floor, in dBFS. A peak at or below reads `0`.
    static let floorDB: Double = -60

    /// Fill `0...1` for a linear peak amplitude. `nil` (no tap) and any non-positive peak read
    /// **exactly** `0`; full scale (`1.0`) reads `1.0`; a peak past full scale clamps at `1.0`;
    /// between, a straight dB ramp off `floorDB`.
    static func fill(forLinearPeak peak: Float?) -> Double {
        guard let peak, peak > 0 else { return 0 }
        let db = 20 * log10(Double(peak))
        guard db > floorDB else { return 0 }
        return min(1, (db - floorDB) / -floorDB)
    }

    /// How long a published peak stands before a drain that produced nothing is allowed to zero
    /// it. Longer than the ~170 ms a real chunk carries, so an ordinary gap between chunks is
    /// never mistaken for silence; short enough that a tap which stops delivering reads zero
    /// within a meter frame or two.
    static let holdSeconds: TimeInterval = 0.25

    /// What a drain should do with the published level.
    enum Publication: Equatable {
        /// Store this value: a real peak, or an explicit zero once the hold has expired.
        case publish(Float)
        /// Leave the last published value standing.
        case hold
    }

    /// The publish-or-hold decision, taken per drain (issue #100).
    ///
    /// **An empty drain does not publish zero, and that is the whole point.** The engine used to
    /// store `produced > 0 ? peak : 0` unconditionally, but its writer loop naps 5 ms when the ring
    /// is empty while a real chunk carries ~170 ms of audio — so roughly thirty empty drains
    /// stamped 0 over every real peak, and the published value was true for the sub-millisecond it
    /// took to write the chunk. Sampled at 20 Hz against a master whose last four seconds peaked at
    /// −2.0 dBFS, a 54-second capture caught **two** real samples out of 1080. The meter's
    /// documented contract was honoured so precisely that a *live* tap read zero too, because an
    /// empty drain and a dead tap published the identical value.
    ///
    /// **A dead tap still reads exactly zero**, by both routes that actually produce one:
    ///
    /// - a **soft-fault** tap delivers all-zero chunks, which are `producedSamples > 0` carrying a
    ///   zero peak, and publish immediately;
    /// - a **famine** delivers nothing at all, and falls to the hold, reading zero a quarter-second
    ///   later.
    ///
    /// What no longer reads as a dead tap is a live one between chunks.
    static func publication(producedSamples: Int, peak: Float,
                            now: TimeInterval, lastPublishedAt: TimeInterval) -> Publication {
        guard producedSamples <= 0 else { return .publish(peak) }
        return now - lastPublishedAt >= holdSeconds ? .publish(0) : .hold
    }
}
