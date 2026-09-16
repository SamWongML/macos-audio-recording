import Foundation
import Testing

@testable import AppTape

/// The editor's coordinator, and the rule it exists to keep: the selection stays honest as the
/// folder changes underneath it.
@MainActor
struct EditorModelTests {

    /// The model under test with a store over an in-memory folder, and the Export coordinator handed
    /// back so a case can park it in a phase and read it afterwards.
    @MainActor
    struct Rig {
        let reader = StubRecordingReader()
        let coordinator: ExportCoordinator
        let model: EditorModel

        init() {
            let coordinator = ExportCoordinator()
            self.coordinator = coordinator
            // A directory that does not exist, so `start` establishes no real folder watch.
            self.model = EditorModel(
                store: LibraryStore(
                    directory: URL(filePath: "/AppTapeTests-\(UUID().uuidString)"),
                    reader: reader),
                player: AudioPlayer(),
                correction: LoudnessCorrectionModel(),
                coordinator: coordinator,
                preference: ExportPreference(
                    defaults: UserDefaults(suiteName: "apptape-tests-\(UUID().uuidString)")!))
        }
    }

    // MARK: - What is selected when the editor opens

    /// Opening the editor lists the folder exactly once. `start()` already re-lists on its first
    /// call, and opening the window activates the app, which re-lists again.
    @Test func openingTheEditorListsTheFolderOnce() {
        let rig = Rig()
        rig.reader.place("one")
        rig.reader.place("two")

        rig.model.activate()

        #expect(rig.reader.listCount == 1)
    }

    /// The path capture takes on every Stop: the editor is opened naming the Recording just made,
    /// which the store has only just listed.
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

    /// Nothing pending, first open: the newest Recording, which is the store's own order.
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

    /// An empty Library selects nothing, and — the distinction that matters — does not
    /// report a vanish.
    @Test func anEmptyLibraryDoesNotCloseTheEditor() {
        let rig = Rig()

        rig.model.activate()

        #expect(rig.model.selection == nil)
        #expect(rig.model.vanishedTick == 0)
    }

    // MARK: - What happens when the open Recording changes underneath

    /// the mechanism, and the reason `Recording` is a reference type: the store re-adopts a file
    /// that grew, so the object the editor is rendering is now the stale one and the selection has
    /// to rebind to the fresh object rather than to the same url.
    @Test func theOpenRecordingReAdoptedRebindsToTheFreshObject() {
        let rig = Rig()
        let opened = rig.reader.place("growing", seconds: 2)
        rig.model.activate(selecting: opened.url)
        #expect(rig.model.selection === opened)

        // The same file, longer, and a fresh reading of it.
        let grown = Recording.stub(
            "growing", seconds: 90,
            byteCount: (opened.openedByteCount ?? 0) + 1,
            identity: opened.fileIdentity)
        rig.reader.grow(opened, to: grown)
        rig.model.activate()

        #expect(rig.model.selection === grown)
        #expect(rig.model.selection !== opened)
        #expect(rig.model.player.recording === grown)
    }

    /// The open Recording disappearing from the folder is the one case that closes the window: the
    /// selection goes, playback stops, a running Export is cancelled because the editor has
    /// navigated away from it, and the tick is what the view closes on.
    @Test func theOpenRecordingVanishingClosesTheEditorAndCancelsTheExport() {
        let rig = Rig()
        let opened = rig.reader.place("about to vanish")
        rig.model.activate(selecting: opened.url)
        // Parked *after* the open: opening is itself a selection change, which cancels, so an
        // Export started before it would already be idle and the case would prove nothing.
        rig.coordinator.enter(phase: .running(fraction: 0.4), subject: opened)

        rig.reader.remove(opened)
        rig.model.activate()

        #expect(rig.model.selection == nil)
        #expect(rig.model.vanishedTick == 1)
        #expect(rig.coordinator.phase == .idle)
        #expect(rig.coordinator.subjectURL == nil)
        #expect(rig.model.player.isPlaying == false)
    }

    // MARK: - Navigating away from an Export

    /// Selecting a different Recording cancels a running Export, unwarned. The destination is
    /// untouched, so it costs only redoable work.
    @Test func selectingADifferentRecordingCancelsARunningExport() {
        let rig = Rig()
        let exporting = rig.reader.place("exporting", recordedAt: Date(timeIntervalSince1970: 2_000))
        let other = rig.reader.place("other", recordedAt: Date(timeIntervalSince1970: 1_000))
        rig.model.activate(selecting: exporting.url)
        rig.coordinator.enter(phase: .running(fraction: 0.4), subject: exporting)

        rig.model.select(other)

        #expect(rig.coordinator.phase == .idle)
    }

    /// And a re-selection of the same Recording does not: a folder refresh re-selecting what is
    /// already open would otherwise clear a success the user has not read yet.
    @Test func reSelectingTheSameRecordingLeavesAFinishedTellingStanding() {
        let rig = Rig()
        let placed = rig.reader.place("exported")
        rig.model.activate(selecting: placed.url)
        rig.coordinator.enter(phase: .succeeded(url: placed.url), subject: placed)

        // The same Recording, selected again — what a folder refresh does.
        rig.model.select(placed)

        #expect(rig.coordinator.phase == .succeeded(url: placed.url))
    }
}
