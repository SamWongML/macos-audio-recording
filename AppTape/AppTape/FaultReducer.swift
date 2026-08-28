//
//  FaultReducer.swift
//  AppTape
//

import Foundation

/// The Capture Engine's fault-policy seam: a pure value reducer, off the realtime thread, that
/// turns observations of the tap's health into "rebuild" or "end", encoding the split ADR-0010
/// draws between two kinds of fault.
///
/// The split exists because **a tap that has died and a Source that has gone quiet are the same
/// observation** — callbacks arriving at the full rate with every sample zero, `isRunningOutput`
/// true in both cases. So:
///
/// - A **soft fault** is all-zero-while-running, ambiguous with real silence. It gets **one**
///   rebuild, **never counts toward exhaustion, and never ends a Recording** — a thirty-second
///   pause in a podcast must not destroy the Recording. It re-arms only on the next non-zero sample.
/// - A **hard fault** is unambiguous — a Core Audio error, a callback famine — and spends one of
///   three attempts, spaced 1 s / 2 s / 4 s so restore keeps first refusal and the end lands ~7 s
///   after an unrecoverable fault. A **format mismatch ends at once**, spending no attempt.
///
/// The reducer only decides *when*; the engine executes the rebuild (destroy-and-recreate the tap,
/// re-resolving the Source's processes) and reports back the next fault or a recovery.
nonisolated struct FaultReducer {
    enum Action: Equatable {
        case none
        /// Rebuild the tap now. Both soft and hard rebuilds tag their padded gap `rebuild`; the
        /// reducer does not distinguish them here — the engine sets `rebuildInFlight` either way.
        case rebuild
        case end(RecordingEndReason)
    }

    private var soft = SoftFaultDetector()
    private var hard = HardFaultCoordinator()

    /// Fold in one per-tick observation of the audio (the soft path).
    ///
    /// A non-zero sample is a **recovery**: it re-arms the soft one-shot *and* cancels any pending
    /// hard rebuild, which is how restore keeps first refusal — a Source that quit and relaunched
    /// brings its audio back inside the 1 s backoff, before the first rebuild ever fires.
    mutating func observe(allZero: Bool, isRunningOutput: Bool, now: TimeInterval) -> Action {
        if !allZero {
            hard.recovered()
            _ = soft.receive(allZero: false, isRunningOutput: isRunningOutput, now: now)
            return .none
        }
        if soft.receive(allZero: true, isRunningOutput: isRunningOutput, now: now) {
            return .rebuild
        }
        return .none
    }

    /// A hard fault was observed — a Core Audio error or a callback famine. Schedules a backoff, or
    /// ends the Recording if the three attempts are already spent.
    mutating func hardFault(now: TimeInterval) -> Action { hard.hardFault(now: now) }

    /// A rebuilt tap's format did not match the master's ASBD: end at once, no attempt spent.
    mutating func formatMismatch() -> Action { .end(.formatMismatch) }

    /// Time passing. Fires a scheduled hard rebuild when its backoff elapses.
    mutating func poll(now: TimeInterval) -> Action { hard.poll(now: now) }
}

/// The soft (ambiguous-silence) detector: all-zero for 10 s while output runs → one rebuild, ever,
/// per audio epoch. Never ends a Recording. A twin of `DenialDetector`, but where denial disarms
/// permanently at the first sound, this one re-arms on every return of audio, because a
/// mid-Recording silence is exactly what it must survive without spending anything (ADR-0010).
nonisolated struct SoftFaultDetector {
    /// Ten seconds — ten times the ~1 s restore window, so it can never race the free recovery; and
    /// longer than essentially all in-content dead air, so a podcast's pauses make no Seam (ADR-0010).
    static let window: TimeInterval = 10

    /// Start of the current continuous all-zero-while-running run, or nil when none is in progress.
    private var runStart: TimeInterval?
    /// The one-shot latch: true once this epoch's single rebuild has fired. Cleared by any non-zero
    /// sample, which is what "re-arms on the next non-zero sample" means.
    private var firedThisEpoch = false

    /// Fold in one observation. Returns true exactly once per epoch — on the tick the 10 s window
    /// closes — telling the engine to fire the one soft rebuild.
    mutating func receive(allZero: Bool, isRunningOutput: Bool, now: TimeInterval) -> Bool {
        guard allZero else {
            // Audio is back: re-arm the one-shot and reset the window. A momentary drop resets too,
            // which is why real dead air between phrases never accumulates toward the threshold.
            firedThisEpoch = false
            runStart = nil
            return false
        }
        guard isRunningOutput else {
            // Paused / not producing output — ordinary silence, not a fault. Reset the window.
            runStart = nil
            return false
        }
        if firedThisEpoch { return false }
        let start = runStart ?? now
        runStart = start
        if now - start >= Self.window {
            firedThisEpoch = true
            runStart = nil
            return true
        }
        return false
    }
}

/// The hard (unambiguous) fault coordinator: three rebuild attempts spaced 1 s / 2 s / 4 s, then
/// exhaustion ends the Recording. A format mismatch ends immediately without spending an attempt.
/// A genuine recovery (audio flowing again) cancels a pending rebuild and restores the full budget.
nonisolated struct HardFaultCoordinator {
    /// The backoff before attempt 1, 2, 3. The doubling keeps restore's first refusal on this path
    /// too and puts the end about 1 + 2 + 4 = 7 s after an unrecoverable fault (ADR-0010).
    static let backoffs: [TimeInterval] = [1, 2, 4]

    /// Rebuild attempts already fired this fault sequence.
    private var attemptsUsed = 0
    /// Monotonic time at which the next scheduled rebuild should fire, or nil when none is pending.
    private var pendingFireAt: TimeInterval?

    /// A hard fault was observed. Schedules the next backoff, or — if all three attempts are already
    /// spent — ends the Recording as recovery-exhausted.
    mutating func hardFault(now: TimeInterval) -> FaultReducer.Action {
        if attemptsUsed >= Self.backoffs.count {
            return .end(.recoveryExhausted)
        }
        // Only the first fault of a sequence sets the clock; a repeated report while already waiting
        // does not restart it.
        if pendingFireAt == nil {
            pendingFireAt = now + Self.backoffs[attemptsUsed]
        }
        return .none
    }

    /// Time passing. Fires the scheduled rebuild once its backoff has elapsed, spending an attempt.
    mutating func poll(now: TimeInterval) -> FaultReducer.Action {
        guard let fireAt = pendingFireAt, now >= fireAt else { return .none }
        pendingFireAt = nil
        attemptsUsed += 1
        return .rebuild
    }

    /// Audio is flowing again: cancel any pending rebuild and hand back the full attempt budget, so
    /// a later, separate fault starts fresh. This is the restore-beats-rebuild cancellation.
    mutating func recovered() {
        pendingFireAt = nil
        attemptsUsed = 0
    }
}
