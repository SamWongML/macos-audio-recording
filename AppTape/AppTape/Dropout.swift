import Foundation

/// A stretch of silence padded into the master to stand in for audio that never reached it —
/// because a buffer was dropped under load (`overrun`) or capture was interrupted and rebuilt
/// (`rebuild`).
nonisolated struct Dropout: Equatable, Sendable {
    nonisolated enum Cause: String, Sendable, CaseIterable {
        /// A dropped buffer: the realtime ring overran and the writer padded the hole.
        case overrun
        /// The tap died and was rebuilt: the host-time delta across the fault, padded.
        case rebuild
    }

    /// The master frame at which the Dropout begins.
    var start: Int
    /// The Dropout's length in master frames.
    var frames: Int
    var cause: Cause

    /// Where the Dropout begins and ends, in seconds.
    func startSeconds(sampleRate: Double) -> Double { sampleRate > 0 ? Double(start) / sampleRate : 0 }

    /// The lane and the loupe each drew a band from `startSeconds` to `Double(start + frames) /
    /// sampleRate`, spelled out by hand — so a Dropout had one named end and one arithmetic one.
    func endSeconds(sampleRate: Double) -> Double {
        sampleRate > 0 ? Double(start + frames) / sampleRate : 0
    }
}

/// When a Recording's Dropouts are worth report the user about.
enum DropoutSurfacing {
    /// A single Dropout of 250 ms, or a total of 250 ms.
    static let thresholdSeconds: Double = 0.250

    static func totalFrames(_ dropouts: [Dropout]) -> Int { dropouts.reduce(0) { $0 + $1.frames } }

    static func totalSeconds(_ dropouts: [Dropout], sampleRate: Double) -> Double {
        sampleRate > 0 ? Double(totalFrames(dropouts)) / sampleRate : 0
    }

    /// Whether the Recording should carry the mark: any single Dropout ≥ 250 ms, or the total ≥ 250 ms.
    static func isSurfaced(_ dropouts: [Dropout], sampleRate: Double) -> Bool {
        guard sampleRate > 0, !dropouts.isEmpty else { return false }
        let threshold = thresholdSeconds * sampleRate
        if dropouts.contains(where: { Double($0.frames) >= threshold }) { return true }
        return Double(totalFrames(dropouts)) >= threshold
    }

    /// Dropouts big enough to draw as a band in the lane — individually at or over the threshold.
    static func laneVisible(_ dropouts: [Dropout], sampleRate: Double) -> [Dropout] {
        guard sampleRate > 0 else { return [] }
        let threshold = thresholdSeconds * sampleRate
        return dropouts.filter { Double($0.frames) >= threshold }
    }

    /// The rest — recorded but too small to draw, and gathered into the editor's one-line summary.
    static func subThreshold(_ dropouts: [Dropout], sampleRate: Double) -> [Dropout] {
        guard sampleRate > 0 else { return dropouts }
        let threshold = thresholdSeconds * sampleRate
        return dropouts.filter { Double($0.frames) < threshold }
    }
}
