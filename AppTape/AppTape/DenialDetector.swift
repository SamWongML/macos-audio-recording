//
//  DenialDetector.swift
//  AppTape
//

import Foundation

/// Infers a denied *System Audio Recording* grant from the one symptom macOS gives, since it
/// never reports the denial: a denied `AudioDeviceStart` returns `noErr`, installs the IOProc,
/// and calls it at the normal rate **forever with every sample exactly zero** — byte-identical
/// to a Source that happens to be quiet (ADR-0008). So the denial is inferred, not read.
///
/// A pure value reducer, like `CaptureReducer`, so the whole rule is visible to a test off the
/// realtime thread. The Capture Engine's writer thread samples the Source's
/// `kAudioProcessPropertyIsRunningOutput` and folds it in with a monotonic clock; nothing here
/// touches Core Audio or a real clock.
///
/// The rule (ADR-0008): a Recording whose every buffer has been exactly zero **since its first
/// sample**, for `threshold` seconds, while the Source **continuously** reports output, is
/// treated as ungranted. Two clauses keep it narrow and safe:
///
/// - **Since its first sample.** The instant the master begins — a real sound was heard, so the
///   grant plainly exists — the detector disarms *permanently*. This is what makes a mid-Recording
///   silence structurally unable to trigger it: that Source has already delivered audio.
/// - **While output runs.** A Source that is paused (`isRunningOutput` false) is the ordinary
///   arm-then-never-play case, not a denial; the window resets on any drop of output, so real
///   dead air between the press and the first sound never accumulates toward the threshold.
struct DenialDetector {
    /// Seconds of continuous all-zero-since-first-sample, while output runs, after which a denied
    /// grant is inferred. Short because the denied state is unambiguous once output is confirmed
    /// running — the app is producing sound and the tap hears none (ADR-0008).
    static let threshold: TimeInterval = 3

    /// Latches true the instant denial is inferred; never clears within a Recording.
    private(set) var inferred = false

    /// Set once the master has begun — the detector is then disarmed for the Recording's life.
    private var disarmed = false

    /// Monotonic timestamp at which the current continuous all-zero-while-running run began, or
    /// nil when no such run is in progress.
    private var runStart: TimeInterval?

    /// Fold in one observation, taken while the arming window may still be open.
    ///
    /// - Parameters:
    ///   - hasBegun: whether the master has begun (the first sound has been heard). Once true, the
    ///     detector disarms permanently — the "since its first sample" clause.
    ///   - isRunningOutput: whether any process of the Source reports output right now. The window
    ///     only advances while this is true and resets the moment it drops.
    ///   - now: a monotonic timestamp in seconds.
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
