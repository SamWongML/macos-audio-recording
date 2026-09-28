import Foundation
import Testing

@testable import AppTape

@MainActor
struct EditorPresenterTests {
    @Test func openingBeforeTheWindowActionIsReadyIsRemembered() {
        let rig = Rig()
        rig.presenter.open()
        rig.presenter.bind { rig.system.open() }
        #expect(rig.system.windowCount == 1)
        #expect(rig.system.active)
    }

    @Test func returningRevealsTheSameWindowAndClosingAllowsItToReopen() {
        let rig = Rig()
        let window = FakeWindow()
        rig.presenter.bind { rig.system.open() }
        rig.presenter.attach(window)
        window.hidden = true
        window.minimized = true

        rig.presenter.open()
        rig.presenter.open()

        #expect(!window.hidden)
        #expect(!window.minimized)
        #expect(rig.system.active)
        #expect(rig.system.windowCount == 0)
        #expect(rig.model.model.selection == nil)

        rig.presenter.detach(window)
        rig.presenter.open()
        #expect(rig.system.windowCount == 1)
    }

    // MARK: - A Recording the user stopped

    /// The window is where the user pressed Stop, so the Recording is selected in place: nothing is
    /// activated, revealed or opened on top of whatever the user turned to next.
    @Test func aWindowStopSelectsTheSavedRecordingWithoutBringingAnythingForward() {
        let rig = Rig()
        let window = FakeWindow()
        rig.presenter.bind { rig.system.open() }
        rig.presenter.attach(window)
        let older = rig.model.reader.place("older", recordedAt: Date(timeIntervalSince1970: 1_000))
        rig.model.model.select(older)
        window.hidden = true
        let saved = rig.model.reader.place("just saved", recordedAt: Date(timeIntervalSince1970: 2_000))

        rig.presenter.presentSavedRecording(saved.url, stoppedFrom: .window)

        #expect(rig.model.model.selection?.url == saved.url)
        #expect(rig.system.active == false)
        #expect(rig.system.windowCount == 0)
        #expect(window.hidden)
    }

    /// The helper's stop keeps its ending until the helper's own redesign: the editor opens on it.
    @Test func aHelperStopStillOpensTheEditorOnTheSavedRecording() {
        let rig = Rig()
        rig.presenter.bind { rig.system.open() }
        let saved = rig.model.reader.place("just saved")

        rig.presenter.presentSavedRecording(saved.url, stoppedFrom: .helper)

        #expect(rig.system.windowCount == 1)
        #expect(rig.system.active)
        #expect(rig.model.model.selection?.url == saved.url)
    }

    /// Capture and the editor together: browsing an older Recording leaves capture alone, and the
    /// window's Stop selects what was captured once the Library lists it.
    @Test func stoppingFromTheWindowSelectsTheCompletedRecordingOverTheOneBeingBrowsed() {
        let rig = Rig()
        let capture = CaptureRig(presenter: rig.presenter)
        let window = FakeWindow()
        rig.presenter.bind { rig.system.open() }
        rig.presenter.attach(window)
        let older = rig.model.reader.place("older", recordedAt: Date(timeIntervalSince1970: 1_000))
        rig.model.model.activate()
        rig.model.model.select(older)

        let fake = capture.start()
        let master = rig.model.reader.place(
            "Podcast 2026-09-28 at 10.41.07", recordedAt: Date(timeIntervalSince1970: 2_000))
        capture.builder.hooks().onMasterCreated(master.url)

        #expect(capture.run.isRecording)
        #expect(rig.model.model.selection?.url == older.url)
        // The older Recording stays playable and exportable while the new one grows.
        #expect(capture.run.isStillArriving(older) == false)

        fake.outcome = CaptureOutcome(
            result: CaptureResult(url: master.url, frameCount: 48_000, sampleRate: 48_000),
            selfEndReason: nil)
        capture.run.stop(from: .window)

        #expect(rig.model.model.selection?.url == master.url)
        #expect(rig.system.windowCount == 0)
    }

    /// A run that never heard a sound saved nothing, so there is nothing to select and the
    /// Recording being browsed stays selected.
    @Test func stoppingFromTheWindowBeforeAnySoundLeavesTheSelectionAlone() {
        let rig = Rig()
        let capture = CaptureRig(presenter: rig.presenter)
        let window = FakeWindow()
        rig.presenter.bind { rig.system.open() }
        rig.presenter.attach(window)
        let older = rig.model.reader.place("older")
        rig.model.model.activate()
        rig.model.model.select(older)

        capture.start()
        capture.run.stop(from: .window)

        #expect(rig.model.model.selection?.url == older.url)
        #expect(rig.model.model.selectionUnavailable == false)
        #expect(rig.system.active == false)
    }

    /// A run whose report reaches this presenter, the way the production reporter's reaches the app's.
    @MainActor
    final class CaptureRig {
        let builder: FakeCaptureBuilder
        let run: CaptureRun

        init(presenter: EditorPresenter) {
            let builder = FakeCaptureBuilder()
            self.builder = builder
            run = CaptureRun(
                builder: builder, runway: StubRunway(freeBytes: 500_000_000_000),
                reporter: PresentingReporter(presenter: presenter), reader: StubRecordingReader())
        }

        /// Press record from the window and let the bring-up succeed.
        @discardableResult
        func start() -> FakeCapture {
            run.start(CaptureRunTests.Rig.source, now: 0)
            return builder.finish()
        }
    }

    final class FakeWindow: EditorWindow {
        var hidden = false
        var minimized = false
        func reveal() {
            hidden = false
            minimized = false
        }
    }

    final class Rig {
        let model = EditorModelTests.Rig()
        let system = FakeSystem()
        let presenter: EditorPresenter

        init() {
            presenter = EditorPresenter(
                model: model.model,
                activateApplication: { [system] in
                    system.active = true
                })
        }
    }

    final class FakeSystem {
        var active = false
        var windowCount = 0
        func open() { windowCount += 1 }
    }
}
