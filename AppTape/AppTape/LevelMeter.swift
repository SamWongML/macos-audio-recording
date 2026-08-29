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
enum LevelMeter {
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
}
