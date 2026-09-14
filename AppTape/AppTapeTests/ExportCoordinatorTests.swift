//
//  ExportCoordinatorTests.swift
//  AppTapeTests
//

import AVFoundation
import Testing
import Foundation
@testable import AppTape

/// The non-modal export flow's file handling (ADR-0012). The save panel and the state machine are
/// AppKit-bound, but the two properties the acceptance criteria hinge on are testable directly: the
/// atomic swap finishes to the chosen file, and a cancel/failure leaves that file **untouched**
/// because the encode only ever writes the sibling temp.
struct ExportCoordinatorTests {
    private func encode(_ source: URL, to dest: URL, frames: Int64 = 48_000,
                        preset: QualityPreset = .high) throws {
        try ExportEncoder().run(ExportRequest(source: source, destination: dest,
                                              startFrame: 0, frameCount: frames, preset: preset)) { _ in }
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

        #expect(!FileManager.default.fileExists(atPath: temp.path))   // temp consumed by the swap
        let out = try AVAudioFile(forReading: dest)                   // dest is now a real m4a
        #expect(out.length > 0)
    }

    @Test func aNewDestinationNameIsMovedIntoPlace() throws {
        let dir = try AudioFixtures.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = try AudioFixtures.writeCAF(at: dir.appendingPathComponent("master.caf"), seconds: 2)

        let dest = dir.appendingPathComponent("Brand New.m4a")   // does not exist yet
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
        // and never commits, so the destination is exactly as it was (ADR-0012).
        let temp = dir.appendingPathComponent(".apptape-export-\(UUID().uuidString).m4a")
        let encoder = ExportEncoder()
        encoder.cancel()
        #expect(throws: ExportEncoder.Failure.self) {
            try encoder.run(ExportRequest(source: source, destination: temp,
                                          startFrame: 0, frameCount: 48_000, preset: .high)) { _ in }
        }
        try? FileManager.default.removeItem(at: temp)

        #expect(try Data(contentsOf: dest) == Data("ORIGINAL".utf8))   // untouched
    }

    /// **The gate in front of the save panel** (ADR-0046). `export` used to hold two of the five
    /// refusal rules, in a wording of its own, and neither was reachable by a test because reaching
    /// them meant getting past `presentSavePanel`. They are `ExportReadiness`'s now, and every case
    /// here returns *before* any AppKit is touched — which is exactly what each one asserts.
    ///
    /// `@MainActor` at the suite: `ExportCoordinator` and `Recording` both are (ADR-0022), and this
    /// test target does not carry the app's `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
    @MainActor
    struct Refusals {
        /// The state the running app reaches by pressing Export on the Recording being written. The
        /// coordinator had **no rule for it at all** before ADR-0046 — the dock alone refused it,
        /// so any other caller could have encoded a `.caf` still growing under it (ADR-0012).
        @Test func aCapturingRecordingIsRefusedBeforeTheSavePanel() {
            let coordinator = ExportCoordinator()
            let recording = Recording.stub()
            coordinator.export(recording: recording, preset: .high,
                               capture: PreviewCapture.capturing(recording))

            #expect(coordinator.phase == .failed(message: "This Recording is still capturing."))
            #expect(coordinator.subjectURL == recording.url)
        }

        /// A `public.audio`-typed file the decoder cannot open (ADR-0015). The other rule the
        /// coordinator never had: it was refused only because such a file reads back as zero frames,
        /// so it was told *"Nothing in the Trim to export."* for the wrong reason. The frame count
        /// here is deliberately positive, which is what the old arrangement could not survive.
        @Test func anUnopenableRecordingIsRefusedBeforeAnythingElseIsAsked() {
            let coordinator = ExportCoordinator()
            let recording = Recording.stub(seconds: 90, isOpenable: false)
            coordinator.export(recording: recording, preset: .high, capture: PreviewCapture.settled)

            #expect(coordinator.phase == .failed(message: "AppTape can't decode this file."))
        }

        /// The wording that used to differ: the dock said `Nothing in the Trim to export.` and this
        /// said `There is nothing in the Trim to export.` ADR-0042's table is the one that ships.
        @Test func anEmptyTrimIsRefusedInTheDocksWording() {
            let coordinator = ExportCoordinator()
            coordinator.export(recording: .stub(seconds: 0), preset: .high,
                               capture: PreviewCapture.settled)

            #expect(coordinator.phase == .failed(message: "Nothing in the Trim to export."))
        }

        /// A Trim claiming ninety seconds over a file with no frames in it — the seconds↔frames
        /// divergence, from the side that always counted frames. The dock offered an `Export…` button
        /// for this Recording and the click landed here, which is how a refusal became a failure.
        @Test func aTrimWithNoFramesIsRefusedHoweverManySecondsItClaims() {
            let recording = Recording.stub(seconds: 0, storedTrim: Trim(duration: 90))
            #expect(recording.trimmedDuration == 90)          // what the dock used to read
            #expect(recording.trimmedFrameRange.count == 0)   // what the encoder actually gets

            let coordinator = ExportCoordinator()
            coordinator.export(recording: recording, preset: .high, capture: PreviewCapture.settled)
            #expect(coordinator.phase == .failed(message: "Nothing in the Trim to export."))
        }

        /// Faithful-or-refuse (ADR-0015) at the gate. The telling is the dock's **generic** sentence,
        /// not the rung's specific one: ADR-0041 already states `AAC can't encode above 48 kHz` on the
        /// rung above at full strength, and ADR-0042 has the dock name the situation and leave the
        /// specifics there. The specific reason is carried in the refusal, not discarded.
        @Test func anUnencodablePresetIsRefusedInTheDocksWording() {
            let coordinator = ExportCoordinator()
            let recording = Recording.stub("ZZ Probe 96k", sampleRate: 96_000)
            coordinator.export(recording: recording, preset: .high, capture: PreviewCapture.settled)

            #expect(coordinator.phase == .failed(message: "This quality can't encode this file."))
            // The same source on the rung that can encode it is not refused — so the guard is about
            // the preset, never the file alone. (`.master` would reach the save panel, so this asks
            // `ExportReadiness` directly rather than driving AppKit.)
            #expect(ExportReadiness.evaluate(isOpenable: true, isCapturing: false,
                                             trimmedFrameCount: recording.trimmedFrameRange.count,
                                             preset: .master, format: recording.sourceFormat,
                                             isExporting: false) == .ready)
        }

        /// `guard case .idle` is **not** the one-at-a-time rule. It also holds a finished telling in
        /// place until it is dismissed, which is what the inspector's `Retry…` relies on — it calls
        /// `cancel()` first, and only then does a second `export` get through.
        @Test func aCallDuringASucceededTellingIsStillSwallowed() {
            let coordinator = ExportCoordinator()
            let recording = Recording.stub()
            coordinator.enter(phase: .succeeded(url: recording.url), subject: recording)

            coordinator.export(recording: recording, preset: .high, capture: PreviewCapture.settled)
            #expect(coordinator.phase == .succeeded(url: recording.url))   // unchanged, not refused

            // And a cancel reopens it: the refusal below proves the call now gets past the guard.
            coordinator.cancel()
            coordinator.export(recording: .stub(seconds: 0), preset: .high,
                               capture: PreviewCapture.settled)
            #expect(coordinator.phase == .failed(message: "Nothing in the Trim to export."))
        }
    }

    /// **The telling's subject is the Recording, not the path it had at launch** (issue #127).
    ///
    /// A rename moves the file and the store relocates the *same object* (ADR-0006/-0020), so a
    /// coordinator that had copied the url was left naming a file that no longer exists. The dock
    /// asks `subjectURL == recording.url` before it renders a phase, so the running Recording lost
    /// its own progress bar and Cancel button mid-encode and read `An Export is already running.`
    /// instead, while the encode — snapshotted at launch, and reading a file it already has open —
    /// ran to completion invisibly. Only the *telling* ever broke, which is why the fix is the
    /// coordinator's identity and not the view's comparison.
    ///
    /// `@MainActor` at the suite for the reason `Refusals` carries it: `ExportCoordinator` and
    /// `Recording` both are (ADR-0022), and this target does not carry the app's default isolation.
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

            #expect(coordinator.subjectURL == renamed)               // the dock still matches
            #expect(coordinator.phase == .running(fraction: 0.42))   // and the encode is untouched
        }

        /// And the subject is still asked *where it is*, not *which object it is* — because the
        /// Recording on screen may be a fresh reading of the same file (ADR-0021): a different
        /// object at the same path, which the user has navigated nowhere to reach. Comparing
        /// objects would take the progress bar away from that one exactly as the url took it away
        /// from a rename.
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
