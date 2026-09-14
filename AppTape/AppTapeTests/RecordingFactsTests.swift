import Testing
import Foundation
@testable import AppTape

/// What a `Recording` says about itself, now that saying it costs nothing.
@MainActor
struct RecordingFactsTests {

    // MARK: - The Source: a stored xattr over a live parse

    @Test func theSourceXattrWinsOverTheFilename() {
        // Capture writes the xattr, so a Recording knows where it came from even when its name no
        // longer says.
        let recording = Recording.stub("Google Chrome 2026-09-13 at 21.51.03", storedSource: "Zoom")
        #expect(recording.source == "Zoom")
    }

    @Test func withNoXattrAGeneratedNameParsesToItsSource() {
        // A Recording that lost its attributes — a round trip through a FAT volume or a share —
        // still knows its Source, because capture's own filename carries it.
        let recording = Recording.stub("Google Chrome 2026-09-13 at 21.51.03", storedSource: nil)
        #expect(recording.source == "Google Chrome")
    }

    @Test func withNoXattrAUsersNameIsItsOwnSource() {
        let recording = Recording.stub("Interview", storedSource: nil)
        #expect(recording.source == "Interview")
        #expect(recording.displayName == "Interview")
    }

    @Test func parsedSourceKeepsAWholeNameThatCarriesNoDate() {
        #expect(Recording.parsedSource(from: "Interview") == "Interview")
        #expect(Recording.parsedSource(from: "Google Chrome 2026-09-13 at 21.51.03") == "Google Chrome")
        // A Source with digits in it is not mistaken for the date pattern.
        #expect(Recording.parsedSource(from: "Logic Pro 11 2026-09-13 at 21.51.03") == "Logic Pro 11")
    }

    @Test func displayNameIsTheSourceUntilTheUserNamesIt() {
        // while the filename is capture's, it says nothing the row is not already showing, so the
        // row shows the Source.
        #expect(Recording.stub("Google Chrome 2026-09-13 at 21.51.03").displayName == "Google Chrome")
        #expect(Recording.stub("Interview").displayName == "Interview")
    }

    /// The reason only *half* of `source` is a stored fact.
    @Test func aRenamedFileWithNoXattrRederivesItsSource() {
        let recording = Recording.stub("Google Chrome 2026-09-13 at 21.51.03", storedSource: nil)
        #expect(recording.source == "Google Chrome")

        recording.relocate(to: URL(filePath: "/Library/Interview.caf"))
        #expect(recording.source == "Interview")
        #expect(recording.displayName == "Interview")
        #expect(recording.windowSubtitle.isEmpty)   // the origin is the title; there is nothing to add
    }

    /// The xattr, by contrast, is written once at capture and never rewritten — so it survives the
    /// rename, which is exactly what the window's subtitle wants.
    @Test func aRenamedFileKeepsTheSourceItsXattrRecorded() {
        let recording = Recording.stub("Google Chrome 2026-09-13 at 21.51.03", storedSource: "Google Chrome")
        recording.relocate(to: URL(filePath: "/Library/Interview.caf"))
        #expect(recording.source == "Google Chrome")
        #expect(recording.displayName == "Interview")
    }

    // MARK: - The window's two lines (findings 2 and 32)

    @Test func theWindowSubtitleNeverRepeatsTheTitle() {
        // Generated name: the title *is* the Source, so the subtitle says when instead.
        let recording = Recording.stub("Google Chrome 2026-09-13 at 21.51.03",
                                       recordedAt: Date(timeIntervalSince1970: 1_757_800_000))
        #expect(recording.displayName == "Google Chrome")
        #expect(!recording.windowSubtitle.contains("Google Chrome"))
        #expect(!recording.windowSubtitle.isEmpty)
    }

    @Test func theWindowSubtitleSaysTheSourceOnceTheTitleStopsBeingIt() {
        let recording = Recording.stub("Interview", storedSource: "Google Chrome",
                                       recordedAt: Date(timeIntervalSince1970: 1_757_800_000))
        #expect(recording.displayName == "Interview")
        #expect(recording.windowSubtitle.hasPrefix("Google Chrome · "))
    }

    @Test func theWindowSubtitleWithNoDateIsTheOriginAlone() {
        // No dangling separator when there is only one thing to say.
        let recording = Recording.stub("Interview", storedSource: "Google Chrome", recordedAt: nil)
        #expect(recording.windowSubtitle == "Google Chrome")
    }

    // MARK: - The facts are read once, which is the whole point

    /// The sidebar filters on `displayName` and groups on `recordedAt`, both per row, on every body
    /// pass.
    @Test func renderingTheLibraryOverAndOverReadsNothingFurther() {
        let reader = StubRecordingReader()
        for second in 0..<44 {
            reader.place("Google Chrome 2026-09-13 at 21.51.\(String(format: "%02d", second))")
        }
        let store = LibraryStore(directory: URL(filePath: "/Library"), reader: reader)
        store.refresh()
        #expect(store.recordings.count == 44)

        let (adopts, probes) = (reader.adoptCount, reader.probeCount)
        for _ in 0..<100 {
            for recording in store.recordings {
                _ = recording.displayName
                _ = recording.windowSubtitle
                _ = recording.source
                _ = recording.recordedAt
            }
        }
        #expect(reader.adoptCount == adopts)
        #expect(reader.probeCount == probes)
    }

    @Test func groupingTheLibraryTwiceReadsNothing() {
        let reader = StubRecordingReader()
        reader.place("A", recordedAt: Date(timeIntervalSince1970: 1_000))
        reader.place("B", recordedAt: Date(timeIntervalSince1970: 2_000))
        let store = LibraryStore(directory: URL(filePath: "/Library"), reader: reader)
        store.refresh()

        let (adopts, probes) = (reader.adoptCount, reader.probeCount)
        _ = RecordingDay.group(store.recordings)
        _ = RecordingDay.group(store.recordings)
        #expect(reader.adoptCount == adopts)
        #expect(reader.probeCount == probes)
    }

    // MARK: - Staleness, as a pure question

    @Test func aLengthThatMatchesStillDescribesTheFile() {
        let recording = Recording.stub(byteCount: 8_000)
        #expect(recording.stillDescribes(byteCount: 8_000))
        #expect(!recording.stillDescribes(byteCount: 8_001))   // grew
        #expect(!recording.stillDescribes(byteCount: 7_999))   // shrank
    }

    @Test func twoUnreadableLengthsCompareEqual() {
        // A file that cannot be stat'd is left alone rather than churned — the safe direction.
        let recording = Recording.stub(byteCount: nil)
        #expect(recording.stillDescribes(byteCount: nil))
    }

    @Test func aRecordingWhoseLengthWasUnreadableDoesNotDescribeAReadableFile() {
        let recording = Recording.stub(byteCount: nil)
        #expect(!recording.stillDescribes(byteCount: 8_000))
    }

    // MARK: - The Trim a duration implies

    @Test func aSubMinimumRecordingHasAFixedWholeTrim() {
        // A file shorter than the Trim minimum is adopted and listed with the Trim fixed to the
        // whole of it — neither handle moves — and Exports whole.
        let recording = Recording.stub("blip", seconds: 0.1)
        #expect(recording.trim.isFixed)
        #expect(!recording.isTrimmed)
        let (start, count) = recording.trimmedFrameRange
        #expect(start == 0)
        #expect(count == recording.frameCount)
        #expect(count > 0)
    }

    @Test func theTrimmedFrameRangeRoundsSecondsToFrames() {
        // The one place the seconds→frames rounding lives, so Export and the Loudness measurement
        // read exactly the same frames (/-0013).
        let recording = Recording.stub(seconds: 10, storedTrim: Trim(start: 1, end: 2, duration: 10))
        let (start, count) = recording.trimmedFrameRange
        #expect(start == 48_000)
        #expect(count == 48_000)
    }

    @Test func theTrimmedFrameRangeClampsIntoTheFile() {
        // A Trim read against a duration the file no longer has — permits pointing the app at a
        // shorter file of the same name — must land inside the file rather than past its end.
        let recording = Recording.stub(seconds: 5, storedTrim: Trim(start: 1, end: 19, duration: 20))
        let (start, count) = recording.trimmedFrameRange
        #expect(start == 48_000)
        #expect(start + count == recording.frameCount)
    }

    @Test func theTrimmedFrameRangeIsEmptyForAFileThatWouldNotOpen() {
        let recording = Recording.stub("broken", seconds: 0, sampleRate: 0, isOpenable: false)
        #expect(recording.trimmedFrameRange == (0, 0))
        #expect(recording.isEmpty)
        #expect(recording.duration == 0)
    }
}
