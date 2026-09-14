import Foundation

/// Maps a tap's raw linear peak amplitude to a normalized meter fill (0...1), on a decibel scale so
/// ordinary speech is visible next to one loud transient.
nonisolated enum LevelMeter {
    /// The quietest peak the meter shows above the floor, in dBFS. A peak at or below reads `0`.
    static let floorDB: Double = -60

    /// Fill `0...1` for a linear peak amplitude.
    static func fill(forLinearPeak peak: Float?) -> Double {
        guard let peak, peak > 0 else { return 0 }
        let db = 20 * log10(Double(peak))
        guard db > floorDB else { return 0 }
        return min(1, (db - floorDB) / -floorDB)
    }

    /// How long a published peak stands before a drain that produced nothing is allowed to zero it.
    static let holdSeconds: TimeInterval = 0.25

    /// What a drain should do with the published level.
    enum Publication: Equatable {
        /// Store this value: a real peak, or an explicit zero once the hold has expired.
        case publish(Float)
        /// Leave the last published value standing.
        case hold
    }

    /// The publish-or-hold decision, taken per drain.
    static func publication(
        producedSamples: Int, peak: Float,
        now: TimeInterval, lastPublishedAt: TimeInterval
    ) -> Publication {
        guard producedSamples <= 0 else { return .publish(peak) }
        return now - lastPublishedAt >= holdSeconds ? .publish(0) : .hold
    }
}
