//
//  RowRecordGlyphTests.swift
//  AppTapeTests
//

import Testing
@testable import AppTape

/// The row-as-record-control glyph state machine (issue #59): `circle` → pulsing
/// `record.circle.fill`, with the in-flight glyph held back until bring-up passes ~500 ms.
struct RowRecordGlyphTests {
    @Test func aRowThatIsNotRecordingIsIdle() {
        #expect(RowRecordGlyph.state(isRecordingTarget: false, sincePress: nil, hasFirstSound: false) == .idle)
        // Even if some other row is mid-bring-up, this one stays a plain circle.
        #expect(RowRecordGlyph.state(isRecordingTarget: false, sincePress: 2.0, hasFirstSound: false) == .idle)
    }

    @Test func aFreshPressHoldsTheCircleThroughTheGrace() {
        #expect(RowRecordGlyph.state(isRecordingTarget: true, sincePress: nil, hasFirstSound: false) == .armed)
        #expect(RowRecordGlyph.state(isRecordingTarget: true, sincePress: 0.2, hasFirstSound: false) == .armed)
        #expect(RowRecordGlyph.state(isRecordingTarget: true, sincePress: 0.49, hasFirstSound: false) == .armed)
    }

    @Test func bringUpShowsInFlightFromAboutFiveHundredMilliseconds() {
        #expect(RowRecordGlyph.state(isRecordingTarget: true, sincePress: 0.5, hasFirstSound: false) == .inFlight)
        #expect(RowRecordGlyph.state(isRecordingTarget: true, sincePress: 90, hasFirstSound: false) == .inFlight)
    }

    @Test func theFirstSoundIsRecordingRegardlessOfHowFastItArrived() {
        // A snappy start goes straight to recording, skipping the in-flight glyph entirely.
        #expect(RowRecordGlyph.state(isRecordingTarget: true, sincePress: 0.1, hasFirstSound: true) == .recording)
        #expect(RowRecordGlyph.state(isRecordingTarget: true, sincePress: 5.0, hasFirstSound: true) == .recording)
    }

    @Test func onlyInFlightAndRecordingUseTheFilledPulsingGlyph() {
        #expect(RowRecordGlyph.symbolName(.idle) == "circle")
        #expect(RowRecordGlyph.symbolName(.armed) == "circle")
        #expect(RowRecordGlyph.symbolName(.inFlight) == "record.circle.fill")
        #expect(RowRecordGlyph.symbolName(.recording) == "record.circle.fill")

        #expect(RowRecordGlyph.pulses(.idle) == false)
        #expect(RowRecordGlyph.pulses(.armed) == false)
        #expect(RowRecordGlyph.pulses(.inFlight))
        #expect(RowRecordGlyph.pulses(.recording))
    }
}
