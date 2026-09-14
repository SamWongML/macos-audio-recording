import AVFoundation
import Foundation
import Testing

@testable import AppTape

/// The non-modal export flow's file handling.
struct ExportCoordinatorTests {
    private func encode(
        _ source: URL, to dest: URL, frames: Int64 = 48_000,
        preset: QualityPreset = .high
    ) throws {
        try ExportEncoder().run(
            ExportRequest(
                source: source, destination: dest,
                startFrame: 0, frameCount: frames, preset: preset)
        ) { _ in }
    }

    @Test func commitOverASiblingReplacesTheChosenFileAtomically() throws {
        let dir = try AudioFixtures.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = try AudioFixtures.writeCAF(at: dir.appendingPathComponent("master.caf"), seconds: 2)

        // A pre-existing file at the destination the user is overwriting.
        let dest = dir.appendingPathComponent("Export.m4a")
        try Data("ORIGINAL".utf8).write(to: dest)

        // Encode to a sibling temp, then swap it in.
        let temp = dir.appendingPathComponent(".apptape-export-\(UUID().uuidString).m4a")
        try encode(source, to: temp)
        try ExportCoordinator.commit(temp: temp, to: dest)

        #expect(!FileManager.default.fileExists(atPath: temp.path))  // temp consumed by the swap
        let out = try AVAudioFile(forReading: dest)  // dest is now a real m4a
        #expect(out.length > 0)
    }

    @Test func aNewDestinationNameIsMovedIntoPlace() throws {
        let dir = try AudioFixtures.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = try AudioFixtures.writeCAF(at: dir.appendingPathComponent("master.caf"), seconds: 2)

        let dest = dir.appendingPathComponent("Brand New.m4a")  // does not exist yet
        let temp = dir.appendingPathComponent(".apptape-export-\(UUID().uuidString).m4a")
        try encode(source, to: temp)
        try ExportCoordinator.commit(temp: temp, to: dest)

        #expect(FileManager.default.fileExists(atPath: dest.path))
        #expect(!FileManager.default.fileExists(atPath: temp.path))
    }

    @Test func aCancelledExportLeavesTheChosenFileUntouched() throws {
        let dir = try AudioFixtures.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = try AudioFixtures.writeCAF(at: dir.appendingPathComponent("master.caf"), seconds: 2)

        let dest = dir.appendingPathComponent("Keep Me.m4a")
        try Data("ORIGINAL".utf8).write(to: dest)

        // A cancelled encode throws before writing a usable temp; the flow then discards the temp
        // and never commits, so the destination is exactly as it was.
        let temp = dir.appendingPathComponent(".apptape-export-\(UUID().uuidString).m4a")
        let encoder = ExportEncoder()
        encoder.cancel()
        #expect(throws: ExportEncoder.Failure.self) {
            try encoder.run(
                ExportRequest(
                    source: source, destination: temp,
                    startFrame: 0, frameCount: 48_000, preset: .high)
            ) { _ in }
        }
        try? FileManager.default.removeItem(at: temp)

        #expect(try Data(contentsOf: dest) == Data("ORIGINAL".utf8))  // untouched
    }

    /// The gate in front of the save panel.
    @MainActor
    struct Refusals {
        /// The state the running app reaches by pressing Export on the Recording being written.
        @Test func aCapturingRecordingIsRefusedBeforeTheSavePanel() {
            let coordinator = ExportCoordinator()
            let recording = Recording.stub()
            coordinator.export(
                recording: recording, preset: .high,
                capture: PreviewCapture.capturing(recording))

            #expect(coordinator.phase == .failed(message: "This Recording is still capturing."))
            #expect(coordinator.subjectURL == recording.url)
        }

        /// A `public.audio`-typed file the decoder cannot open.
        @Test func anUnopenableRecordingIsRefusedBeforeAnythingElseIsAsked() {
            let coordinator = ExportCoordinator()
            let recording = Recording.stub(seconds: 90, isOpenable: false)
            coordinator.export(recording: recording, preset: .high, capture: PreviewCapture.settled)

            #expect(coordinator.phase == .failed(message: "AppTape can't decode this file."))
        }

        /// The wording that used to differ: the dock said `Nothing in the Trim to export.` and this
        /// said `There is nothing in the Trim to export.` the table is the one that ships.
        @Test func anEmptyTrimIsRefusedInTheDocksWording() {
            let coordinator = ExportCoordinator()
            coordinator.export(
                recording: .stub(seconds: 0), preset: .high,
                capture: PreviewCapture.settled)

            #expect(coordinator.phase == .failed(message: "Nothing in the Trim to export."))
        }

        /// A Trim claiming ninety seconds over a file with no frames in it — the seconds↔frames
        /// divergence, from the side that always counted frames.
        @Test func aTrimWithNoFramesIsRefusedHoweverManySecondsItClaims() {
            let recording = Recording.stub(seconds: 0, storedTrim: Trim(duration: 90))
            #expect(recording.trimmedDuration == 90)  // what the dock used to read
            #expect(recording.trimmedFrameRange.count == 0)  // what the encoder actually gets

            let coordinator = ExportCoordinator()
            coordinator.export(recording: recording, preset: .high, capture: PreviewCapture.settled)
            #expect(coordinator.phase == .failed(message: "Nothing in the Trim to export."))
        }

        /// Faithful-or-refuse at the gate.
        @Test func anUnencodablePresetIsRefusedInTheDocksWording() {
            let coordinator = ExportCoordinator()
            let recording = Recording.stub("ZZ Probe 96k", sampleRate: 96_000)
            coordinator.export(recording: recording, preset: .high, capture: PreviewCapture.settled)

            #expect(coordinator.phase == .failed(message: "This quality can't encode this file."))
            // The same source on the preset row that can encode it is not refused — so the guard is
            // about the preset, never the file alone.
            #expect(
                ExportReadiness.evaluate(
                    isOpenable: true, isCapturing: false,
                    trimmedFrameCount: recording.trimmedFrameRange.count,
                    preset: .master, format: recording.sourceFormat,
                    isExporting: false) == .ready)
        }

        /// `guard case.idle` is not the one-at-a-time rule.
        @Test func aCallDuringASucceededTellingIsStillSwallowed() {
            let coordinator = ExportCoordinator()
            let recording = Recording.stub()
            coordinator.enter(phase: .succeeded(url: recording.url), subject: recording)

            coordinator.export(recording: recording, preset: .high, capture: PreviewCapture.settled)
            #expect(coordinator.phase == .succeeded(url: recording.url))  // unchanged, not refused

            // And a cancel reopens it: the blocker below proves the call now gets past the guard.
            coordinator.cancel()
            coordinator.export(
                recording: .stub(seconds: 0), preset: .high,
                capture: PreviewCapture.settled)
            #expect(coordinator.phase == .failed(message: "Nothing in the Trim to export."))
        }
    }

    /// The report's subject is the Recording, not the path it had at launch.
    @MainActor
    struct Subject {
        /// The case in the ticket: a rename mid-Export, from the sidebar or from Finder — both end
        /// at `Recording.relocate`, so both are this one assertion.
        @Test func aRenamedSubjectTakesItsTellingWithIt() {
            let coordinator = ExportCoordinator()
            let recording = Recording.stub()
            coordinator.enter(phase: .running(fraction: 0.42), subject: recording)

            let renamed = recording.url.deletingLastPathComponent()
                .appendingPathComponent("Interview.caf")
            recording.relocate(to: renamed)

            #expect(coordinator.subjectURL == renamed)  // the dock still matches
            #expect(coordinator.phase == .running(fraction: 0.42))  // and the encode is untouched
        }

        /// And the subject is still asked *where it is*, not *which object it is* — because the
        /// Recording on screen may be a fresh reading of the same file: a different object at the
        /// same path, which the user has navigated nowhere to reach.
        @Test func aFreshReadingOfTheSameFileStillFindsItsTelling() {
            let coordinator = ExportCoordinator()
            let opened = Recording.stub("growing")
            coordinator.enter(phase: .running(fraction: 0.4), subject: opened)

            let reRead = Recording.stub("growing")
            #expect(reRead !== opened)
            #expect(coordinator.subjectURL == reRead.url)
        }

        /// A cancel drops the subject with the phase, so an idle dock keeps no Recording alive
        /// behind it.
        @Test func aCancelLetsTheSubjectGo() {
            let coordinator = ExportCoordinator()
            coordinator.enter(phase: .running(fraction: 0.4), subject: .stub())

            coordinator.cancel()
            #expect(coordinator.subjectURL == nil)
        }
    }
}
