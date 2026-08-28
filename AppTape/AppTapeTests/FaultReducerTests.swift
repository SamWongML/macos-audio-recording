//
//  FaultReducerTests.swift
//  AppTapeTests
//

import Testing
@testable import AppTape

/// The soft/hard fault split (ADR-0010): a 10 s soft one-shot that never ends a Recording and
/// re-arms on the next non-zero sample; hard attempts spaced 1/2/4 s and armed at the first
/// callback; a format mismatch that ends without spending an attempt; restore beating rebuild.
struct FaultReducerTests {

    // MARK: - Soft path

    @Test func softFaultFiresOneRebuildAfterTenSeconds() {
        var d = SoftFaultDetector()
        // All-zero while output runs, but not yet 10 s: nothing fires.
        #expect(d.receive(allZero: true, isRunningOutput: true, now: 0) == false)
        #expect(d.receive(allZero: true, isRunningOutput: true, now: 9.9) == false)
        // At 10 s: the one soft rebuild.
        #expect(d.receive(allZero: true, isRunningOutput: true, now: 10) == true)
    }

    @Test func softFaultIsAOneShotUntilAudioReturns() {
        var d = SoftFaultDetector()
        _ = d.receive(allZero: true, isRunningOutput: true, now: 0)
        #expect(d.receive(allZero: true, isRunningOutput: true, now: 10) == true)
        // It has fired: staying silent another 10 s fires nothing more — never a second rebuild.
        #expect(d.receive(allZero: true, isRunningOutput: true, now: 20) == false)
        #expect(d.receive(allZero: true, isRunningOutput: true, now: 30) == false)
        // A non-zero sample re-arms it; a fresh 10 s of silence fires again.
        #expect(d.receive(allZero: false, isRunningOutput: true, now: 31) == false)
        #expect(d.receive(allZero: true, isRunningOutput: true, now: 31) == false)
        #expect(d.receive(allZero: true, isRunningOutput: true, now: 41) == true)
    }

    @Test func aMomentaryDropResetsTheSoftWindow() {
        var d = SoftFaultDetector()
        _ = d.receive(allZero: true, isRunningOutput: true, now: 0)
        _ = d.receive(allZero: true, isRunningOutput: true, now: 8)
        // A momentary non-zero sample at 8 s resets the window.
        _ = d.receive(allZero: false, isRunningOutput: true, now: 8)
        // Silence resumes; it must be a *fresh* 10 s from here, so 9 s later is not enough.
        #expect(d.receive(allZero: true, isRunningOutput: true, now: 8) == false)
        #expect(d.receive(allZero: true, isRunningOutput: true, now: 17) == false)
        #expect(d.receive(allZero: true, isRunningOutput: true, now: 18) == true)
    }

    @Test func pausedOutputNeverManufacturesASoftFault() {
        var d = SoftFaultDetector()
        // All-zero but the Source is paused (not running output): ordinary silence, never a fault,
        // however long it lasts.
        for t in stride(from: 0.0, through: 60, by: 1) {
            #expect(d.receive(allZero: true, isRunningOutput: false, now: t) == false)
        }
    }

    // MARK: - Hard path

    @Test func hardFaultsSpendThreeAttemptsSpacedOneTwoFour() {
        var c = HardFaultCoordinator()
        // Fault 1 → wait 1 s → rebuild (attempt 1).
        #expect(c.hardFault(now: 0) == .none)
        #expect(c.poll(now: 0.9) == .none)
        #expect(c.poll(now: 1.0) == .rebuild)
        // The rebuild faulted again → wait 2 s → rebuild (attempt 2).
        #expect(c.hardFault(now: 1.0) == .none)
        #expect(c.poll(now: 2.9) == .none)
        #expect(c.poll(now: 3.0) == .rebuild)
        // Again → wait 4 s → rebuild (attempt 3).
        #expect(c.hardFault(now: 3.0) == .none)
        #expect(c.poll(now: 6.9) == .none)
        #expect(c.poll(now: 7.0) == .rebuild)
        // A fourth fault: the budget is spent → end.
        #expect(c.hardFault(now: 7.0) == .end(.recoveryExhausted))
    }

    @Test func recoveryDuringBackoffCancelsTheRebuild() {
        var c = HardFaultCoordinator()
        // A hard fault schedules a rebuild 1 s out — restore's first-refusal window.
        #expect(c.hardFault(now: 0) == .none)
        // Audio returns before the rebuild fires: cancel it and restore the budget.
        c.recovered()
        #expect(c.poll(now: 5) == .none)   // never fires — restore beat rebuild
        // A later, separate fault starts fresh with the full three attempts.
        #expect(c.hardFault(now: 10) == .none)
        #expect(c.poll(now: 11) == .rebuild)
    }

    @Test func aRepeatedHardFaultWhileWaitingDoesNotRestartTheClock() {
        var c = HardFaultCoordinator()
        #expect(c.hardFault(now: 0) == .none)     // fire at 1.0
        #expect(c.hardFault(now: 0.5) == .none)   // still fire at 1.0, not 1.5
        #expect(c.poll(now: 1.0) == .rebuild)
    }

    @Test func formatMismatchEndsAtOnceSpendingNoAttempt() {
        var r = FaultReducer()
        #expect(r.formatMismatch() == .end(.formatMismatch))
        // No attempt was spent: a subsequent hard fault still has its full 1 s backoff and budget.
        #expect(r.hardFault(now: 0) == .none)
        #expect(r.poll(now: 1.0) == .rebuild)
    }

    // MARK: - Composition

    @Test func softNeverEndsEvenAcrossManyEpochs() {
        var r = FaultReducer()
        for epoch in 0..<5 {
            let base = Double(epoch) * 100
            // 10 s of silence → a soft rebuild, never an end.
            _ = r.observe(allZero: true, isRunningOutput: true, now: base)
            let action = r.observe(allZero: true, isRunningOutput: true, now: base + 10)
            #expect(action == .rebuild)
            // Audio returns to re-arm for the next epoch.
            #expect(r.observe(allZero: false, isRunningOutput: true, now: base + 11) == .none)
        }
    }

    @Test func aNonZeroSampleRecoversAPendingHardRebuild() {
        var r = FaultReducer()
        // A hard fault schedules a rebuild 1 s out.
        #expect(r.hardFault(now: 0) == .none)
        // A non-zero sample (audio flowing again) recovers it before it fires.
        #expect(r.observe(allZero: false, isRunningOutput: true, now: 0.2) == .none)
        #expect(r.poll(now: 1.0) == .none)   // the pending rebuild was cancelled
    }
}
