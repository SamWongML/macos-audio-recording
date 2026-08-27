//
//  CaptureReducerTests.swift
//  AppTapeTests
//

import Testing
@testable import AppTape

/// The reducer encodes ADR-0016: a Recording begins at the first sound, the head
/// is elided, interior silence is kept, and arm-then-never-play saves nothing.
struct CaptureReducerTests {
    @Test func silenceBeforeFirstSoundIsElidedAndCountsNothing() {
        var reducer = CaptureReducer()
        #expect(reducer.receive(frameCount: 512, firstNonSilentFrame: nil) == .elide)
        #expect(reducer.receive(frameCount: 512, firstNonSilentFrame: nil) == .elide)
        #expect(reducer.hasBegun == false)
        #expect(reducer.masterFrames == 0)
    }

    @Test func firstSoundBeginsTheMasterAndSkipsTheLeadingSilence() {
        var reducer = CaptureReducer()
        // A 512-frame chunk whose first 100 frames are silent, then sound.
        #expect(reducer.receive(frameCount: 512, firstNonSilentFrame: 100) == .begin(skipLeadingFrames: 100))
        #expect(reducer.hasBegun)
        // Only the frames from the first sound onward are the master's.
        #expect(reducer.masterFrames == 412)
    }

    @Test func aFullyAudibleFirstChunkBeginsAtFrameZero() {
        var reducer = CaptureReducer()
        #expect(reducer.receive(frameCount: 512, firstNonSilentFrame: 0) == .begin(skipLeadingFrames: 0))
        #expect(reducer.masterFrames == 512)
    }

    @Test func interiorSilenceAfterFirstSoundIsKept() {
        var reducer = CaptureReducer()
        _ = reducer.receive(frameCount: 512, firstNonSilentFrame: 0)
        // A silent chunk *after* the master has begun is appended, not elided —
        // it lands as real zero-frames so Trim points do not shift (ADR-0016).
        #expect(reducer.receive(frameCount: 512, firstNonSilentFrame: nil) == .append)
        #expect(reducer.receive(frameCount: 512, firstNonSilentFrame: 300) == .append)
        #expect(reducer.masterFrames == 512 * 3)
    }

    @Test func armThenNeverPlayNeverBegins() {
        var reducer = CaptureReducer()
        // Many silent callbacks (something else on the system is playing) but the
        // Source itself never makes a sound.
        for _ in 0..<200 { _ = reducer.receive(frameCount: 512, firstNonSilentFrame: nil) }
        #expect(reducer.hasBegun == false)
        #expect(reducer.masterFrames == 0)
    }

    @Test func masterFramesAccumulateAcrossChunks() {
        var reducer = CaptureReducer()
        _ = reducer.receive(frameCount: 512, firstNonSilentFrame: 0)
        _ = reducer.receive(frameCount: 480, firstNonSilentFrame: nil)
        _ = reducer.receive(frameCount: 512, firstNonSilentFrame: nil)
        #expect(reducer.masterFrames == 512 + 480 + 512)
    }
}
