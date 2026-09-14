//
//  EditorModelTests.swift
//  AppTapeTests
//

import Foundation
import Testing
@testable import AppTape

/// The editor's coordinator, and the rule it exists to keep: **the selection stays honest as the
/// folder changes underneath it** (ADR-0021, ADR-0006, ADR-0012).
///
/// It had no tests until it accepted its world (ADR-0045). Every case here turns on a Library that
/// changes between two opens — a Recording arriving, growing, or vanishing — which needed a store
/// with no disk behind it and Export objects nothing else is watching.
@MainActor
struct EditorModelTests {

    /// The model under test with a store over an in-memory folder, and the Export coordinator handed
    /// back so a case can park it in a phase and read it afterwards.
    ///
    /// Explicitly `@MainActor`: a nested type does not inherit its enclosing type's isolation, and
    /// this test target does not carry the app's `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
    @MainActor
    struct Rig {
        let reader = StubRecordingReader()
        let coordinator: ExportCoordinator
        let model: EditorModel

        init() {
            let coordinator = ExportCoordinator()
            self.coordinator = coordinator
            // A directory that does not exist, so `start()` establishes no real folder watch. The
            // stub ignores it and answers with what the test placed.
            self.model = EditorModel(store: LibraryStore(directory: URL(filePath: "/AppTapeTests-\(UUID().uuidString)"),
                                                         reader: reader),
                                     player: AudioPlayer(),
                                     correction: LoudnessCorrectionModel(),
                                     coordinator: coordinator,
                                     preference: ExportPreference(defaults: UserDefaults(suiteName: "apptape-tests-\(UUID().uuidString)")!))
        }
    }

    // MARK: - What is selected when the editor opens

    /// The path capture takes on every Stop: the editor is opened naming the Recording just made,
    /// which the store has only just listed (ADR-0016).
    @Test func theRecordingJustCapturedIsSelectedOnceItLists() {
        let rig = Rig()
        rig.reader.place("older", recordedAt: Date(timeIntervalSince1970: 1_000))
        let justMade = rig.reader.place("just made", recordedAt: Date(timeIntervalSince1970: 2_000))

        rig.model.activate(selecting: justMade.url)
        #expect(rig.model.selection?.url == justMade.url)
    }

    /// A pending selection is spent, not standing. Opening the editor again must not drag the
    /// selection back to the Recording captured an hour ago.
    @Test func aPendingSelectionIsSpentOnceAndDoesNotReassertItself() {
        let rig = Rig()
        let captured = rig.reader.place("captured", recordedAt: Date(timeIntervalSince1970: 2_000))
        let other = rig.reader.place("other", recordedAt: Date(timeIntervalSince1970: 1_000))

        rig.model.activate(selecting: captured.url)
        rig.model.select(other)
        rig.model.activate()

        #expect(rig.model.selection?.url == other.url)
    }

    /// Nothing pending, first open: the newest Recording, which is the store's own order (ADR-0031).
    @Test func theNewestRecordingIsSelectedOnTheFirstOpenWithNothingPending() {
        let rig = Rig()
        rig.reader.place("older", recordedAt: Date(timeIntervalSince1970: 1_000))
        let newest = rig.reader.place("newest", recordedAt: Date(timeIntervalSince1970: 2_000))

        rig.model.activate()
        #expect(rig.model.selection?.url == newest.url)
    }

    /// And only on the *first* open: a Recording the user picked themselves is not replaced by the
    /// newest one the next time the window opens.
    @Test func aRecordingTheUserPickedSurvivesALaterOpen() {
        let rig = Rig()
        let older = rig.reader.place("older", recordedAt: Date(timeIntervalSince1970: 1_000))
        rig.reader.place("newest", recordedAt: Date(timeIntervalSince1970: 2_000))

        rig.model.activate()
        rig.model.select(older)
        rig.model.activate()

        #expect(rig.model.selection?.url == older.url)
    }

    /// An empty Library selects nothing, and — the distinction that matters — does **not** report a
    /// vanish. "Selection went nil" happens here too, and closing the window on it would close the
    /// editor of a user who has simply deleted everything.
    @Test func anEmptyLibraryDoesNotCloseTheEditor() {
        let rig = Rig()

        rig.model.activate()

        #expect(rig.model.selection == nil)
        #expect(rig.model.vanishedTick == 0)
    }

    // MARK: - What happens when the open Recording changes underneath

    /// ADR-0021's mechanism, and the reason `Recording` is a reference type: the store re-adopts a
    /// file that grew, so the object the editor is rendering is now the stale one and the selection
    /// has to rebind to the fresh object rather than to the same url.
    @Test func theOpenRecordingReAdoptedRebindsToTheFreshObject() {
        let rig = Rig()
        let opened = rig.reader.place("growing", seconds: 2)
        rig.model.activate(selecting: opened.url)
        #expect(rig.model.selection === opened)

        // The same file, longer, and a fresh reading of it (ADR-0021).
        let grown = Recording.stub("growing", seconds: 90,
                                   byteCount: (opened.openedByteCount ?? 0) + 1,
                                   identity: opened.fileIdentity)
        rig.reader.grow(opened, to: grown)
        rig.model.activate()

        #expect(rig.model.selection === grown)
        #expect(rig.model.selection !== opened)
        #expect(rig.model.player.recording === grown)
    }

    /// The open Recording disappearing from the folder is the one case that closes the window
    /// (ADR-0006): the selection goes, playback stops, a running Export is cancelled because the
    /// editor has navigated away from it (ADR-0012), and the tick is what the view closes on.
    @Test func theOpenRecordingVanishingClosesTheEditorAndCancelsTheExport() {
        let rig = Rig()
        let opened = rig.reader.place("about to vanish")
        rig.model.activate(selecting: opened.url)
        // Parked *after* the open: opening is itself a selection change, which cancels (ADR-0012),
        // so an Export started before it would already be idle and the case would prove nothing.
        rig.coordinator.park(in: .running(fraction: 0.4), subject: opened.url)

        rig.reader.remove(opened)
        rig.model.activate()

        #expect(rig.model.selection == nil)
        #expect(rig.model.vanishedTick == 1)
        #expect(rig.coordinator.phase == .idle)
        #expect(rig.coordinator.subjectURL == nil)
        #expect(rig.model.player.isPlaying == false)
    }

    // MARK: - Navigating away from an Export (ADR-0012)

    /// Selecting a different Recording cancels a running Export, unwarned. The destination is
    /// untouched, so it costs only redoable work.
    @Test func selectingADifferentRecordingCancelsARunningExport() {
        let rig = Rig()
        let exporting = rig.reader.place("exporting", recordedAt: Date(timeIntervalSince1970: 2_000))
        let other = rig.reader.place("other", recordedAt: Date(timeIntervalSince1970: 1_000))
        rig.model.activate(selecting: exporting.url)
        rig.coordinator.park(in: .running(fraction: 0.4), subject: exporting.url)

        rig.model.select(other)

        #expect(rig.coordinator.phase == .idle)
    }

    /// And a re-selection of the same Recording does not: a folder refresh re-selecting what is
    /// already open would otherwise clear a success the user has not read yet.
    @Test func reSelectingTheSameRecordingLeavesAFinishedTellingStanding() {
        let rig = Rig()
        let placed = rig.reader.place("exported")
        rig.model.activate(selecting: placed.url)
        rig.coordinator.park(in: .succeeded(url: placed.url), subject: placed.url)

        // The same Recording, selected again — what a folder refresh does.
        rig.model.select(placed)

        #expect(rig.coordinator.phase == .succeeded(url: placed.url))
    }
}
