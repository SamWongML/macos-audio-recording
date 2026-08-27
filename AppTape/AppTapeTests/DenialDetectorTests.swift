//
//  DenialDetectorTests.swift
//  AppTapeTests
//

import Testing
@testable import AppTape

/// The detector encodes ADR-0008's inference: all-zero-since-first-sample for 3 s while the
/// Source runs output is a denied grant — and the "since its first sample" clause makes a
/// mid-Recording silence structurally unable to trip it.
struct DenialDetectorTests {
    @Test func threeSecondsOfAllZeroWhileRunningInfersDenial() {
        var d = DenialDetector()
        #expect(d.receive(hasBegun: false, isRunningOutput: true, now: 0) == false)
        #expect(d.receive(hasBegun: false, isRunningOutput: true, now: 2.9) == false)
        #expect(d.receive(hasBegun: false, isRunningOutput: true, now: 3.0) == true)
        #expect(d.inferred)
    }

    @Test func underThresholdDoesNotInfer() {
        var d = DenialDetector()
        _ = d.receive(hasBegun: false, isRunningOutput: true, now: 0)
        #expect(d.receive(hasBegun: false, isRunningOutput: true, now: 2.99) == false)
        #expect(d.inferred == false)
    }

    @Test func aDropInOutputResetsTheWindow() {
        var d = DenialDetector()
        // 2.5 s of all-zero while running…
        _ = d.receive(hasBegun: false, isRunningOutput: true, now: 0)
        _ = d.receive(hasBegun: false, isRunningOutput: true, now: 2.5)
        // …then output stops (the Source paused): the run resets.
        #expect(d.receive(hasBegun: false, isRunningOutput: false, now: 2.6) == false)
        // Output resumes: the clock starts over, so 3 s from *here*, not from t=0.
        _ = d.receive(hasBegun: false, isRunningOutput: true, now: 3.0)
        #expect(d.receive(hasBegun: false, isRunningOutput: true, now: 5.5) == false)
        #expect(d.receive(hasBegun: false, isRunningOutput: true, now: 6.0) == true)
    }

    @Test func aPausedSourceNeverInfersHoweverLong() {
        var d = DenialDetector()
        for t in stride(from: 0.0, through: 30.0, by: 1.0) {
            #expect(d.receive(hasBegun: false, isRunningOutput: false, now: t) == false)
        }
        #expect(d.inferred == false)
    }

    @Test func aFirstSoundDisarmsTheDetectorForGood() {
        var d = DenialDetector()
        _ = d.receive(hasBegun: false, isRunningOutput: true, now: 0)
        // The master begins — a real sound was heard.
        #expect(d.receive(hasBegun: true, isRunningOutput: true, now: 0.5) == false)
        // Now a long mid-Recording silence with output running: it must never infer denial,
        // because the grant plainly exists (ADR-0008's "since its first sample").
        #expect(d.receive(hasBegun: false, isRunningOutput: true, now: 10) == false)
        #expect(d.receive(hasBegun: false, isRunningOutput: true, now: 60) == false)
        #expect(d.inferred == false)
    }

    @Test func inferenceLatches() {
        var d = DenialDetector()
        _ = d.receive(hasBegun: false, isRunningOutput: true, now: 0)
        #expect(d.receive(hasBegun: false, isRunningOutput: true, now: 3) == true)
        // Even a subsequent hasBegun / output-drop observation keeps it inferred.
        #expect(d.receive(hasBegun: true, isRunningOutput: false, now: 4) == true)
        #expect(d.inferred)
    }
}
