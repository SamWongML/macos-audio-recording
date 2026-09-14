import Foundation
import Testing

@testable import AppTape

/// How a Recording surfaces the Dropouts it read: the 250 ms single-or-total rule, what draws in
/// the lane, and how the rest are told in one line.
@MainActor
struct RecordingDropoutsTests {
    /// The summary is a `LocalizedStringResource`, so the inflection markup is parsed rather than
    /// printed.
    private func resolved(_ resource: LocalizedStringResource) -> String {
        String(AttributedString(localized: resource).characters)
    }

    @Test func aCleanRecordingIsUnmarked() {
        let recording = Recording.stub(seconds: 3)
        #expect(recording.dropouts.isEmpty)
        #expect(recording.isSurfacedForDropouts == false)
        #expect(recording.laneDropouts.isEmpty)
        #expect(recording.dropoutSummary == nil)
    }

    @Test func aRebuildDropoutSurfacesAndDrawsInTheLane() {
        // A 1 s rebuild Dropout (well over 250 ms) plus a tiny overrun that does not draw.
        let recording = Recording.stub(
            seconds: 5,
            dropouts: [
                Dropout(start: 48_000, frames: 48_000, cause: .rebuild),
                Dropout(start: 200_000, frames: 512, cause: .overrun),
            ])
        #expect(recording.dropouts.count == 2)
        #expect(recording.isSurfacedForDropouts)
        #expect(recording.laneDropouts == [Dropout(start: 48_000, frames: 48_000, cause: .rebuild)])
        #expect(recording.dropoutSummary != nil)
    }

    @Test func onlySubThresholdDropoutsAreNotSurfacedButAreSummarised() {
        // Two 100 ms overruns total 200 ms — under 250 ms, and neither is individually over.
        let recording = Recording.stub(
            seconds: 5,
            dropouts: [
                Dropout(start: 10_000, frames: 4_800, cause: .overrun),
                Dropout(start: 90_000, frames: 4_800, cause: .overrun),
            ])
        #expect(recording.isSurfacedForDropouts == false)  // no glyph
        #expect(recording.laneDropouts.isEmpty)  // nothing drawn in the lane
        #expect(recording.dropoutSummary != nil)  // but told in the one-line summary
    }

    @Test func theSummaryIsInflectedRatherThanPrintedAsMarkup() throws {
        let recording = Recording.stub(
            seconds: 5,
            dropouts: [
                Dropout(start: 48_000, frames: 48_000, cause: .rebuild),
                Dropout(start: 150_000, frames: 48_000, cause: .rebuild),
            ])
        let rendered = resolved(try #require(recording.dropoutSummary))
        #expect(!rendered.contains("^["))
        #expect(!rendered.contains("inflect"))
        #expect(rendered.hasPrefix("2 Dropouts · "))
    }

    /// The singular side of the same markup, so a one-Dropout Recording does not read "1 Dropouts".
    @Test func aSingleDropoutInflectsToTheSingular() throws {
        let recording = Recording.stub(
            seconds: 5,
            dropouts: [
                Dropout(start: 48_000, frames: 48_000, cause: .rebuild)
            ])
        #expect(resolved(try #require(recording.dropoutSummary)).hasPrefix("1 Dropout · "))
    }

    /// Padded silence is spoken at the scale the user can act on: milliseconds under a second,
    /// seconds above. A sub-threshold Dropout is always under one, and a surfaced one usually over.
    @Test func paddingUnderASecondIsSpokenInMilliseconds() throws {
        let recording = Recording.stub(
            seconds: 5,
            dropouts: [
                Dropout(start: 10_000, frames: 4_800, cause: .overrun),
                Dropout(start: 90_000, frames: 4_800, cause: .overrun),
            ])
        let rendered = resolved(try #require(recording.dropoutSummary))
        #expect(rendered == "2 brief Dropouts · 200 ms padded, too short to hear")
    }

    @Test func paddingOverASecondIsSpokenInSeconds() throws {
        let recording = Recording.stub(
            seconds: 10,
            dropouts: [
                Dropout(start: 48_000, frames: 96_000, cause: .rebuild)
            ])
        let rendered = resolved(try #require(recording.dropoutSummary))
        #expect(rendered == "1 Dropout · 2.0 s of silence padded in")
    }
}
