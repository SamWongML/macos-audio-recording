import Foundation

/// Infers a denied *System Audio Recording* grant from the one symptom macOS gives, since it
/// never reports the denial: a denied `AudioDeviceStart` returns `noErr`, installs the IOProc,
/// and calls it at the normal rate **forever with every sample exactly zero** — byte-identical
/// to a Source that happens to be quiet. So the denial is inferred, not read.
nonisolated struct DenialDetector {
    /// Seconds of continuous all-zero-since-first-sample, while output runs, after which a denied
    /// grant is inferred. Short because the denied state is unambiguous once output is confirmed
    /// running — the app is producing sound and the tap hears none.
    static let threshold: TimeInterval = 3

    /// Latches true the instant denial is inferred; never clears within a Recording.
    private(set) var inferred = false

    /// Set once the master has begun — the detector is then disarmed for the Recording's life.
    private var disarmed = false

    /// Monotonic timestamp at which the current continuous all-zero-while-running run began, or
    /// nil when no such run is in progress.
    private var runStart: TimeInterval?

    /// Fold in one observation, taken while the arming window may still be open.
    /// - Parameters:
    /// - Returns: true the instant denial is inferred (and on every call thereafter — it latches).
    mutating func receive(hasBegun: Bool, isRunningOutput: Bool, now: TimeInterval) -> Bool {
        if inferred { return true }
        if disarmed { return false }
        if hasBegun {
            // A real sound was heard: the grant exists. Disarm for good so no later silence,
            // however long, is ever read as a denial.
            disarmed = true
            runStart = nil
            return false
        }
        guard isRunningOutput else {
            // Paused / not producing output — the arm-then-never-play case, not a denial.
            runStart = nil
            return false
        }
        let start = runStart ?? now
        runStart = start
        if now - start >= Self.threshold { inferred = true }
        return inferred
    }
}
