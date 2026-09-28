import Foundation
import Testing

@testable import AppTape

/// The shell both surfaces command: one run, one remembered Source, and presses that never swap an
/// unavailable Source for another app.
@MainActor
struct RecordingControllerTests {

    /// A controller over `CaptureRunTests`' doubles, remembering its Source in a defaults suite of its
    /// own.
    @MainActor
    struct Rig {
        let capture: CaptureRunTests.Rig
        let defaults: UserDefaults
        let controller: RecordingController

        init(freeBytes: Int64? = 500_000_000_000, defaults: UserDefaults = Rig.scratchDefaults()) {
            let capture = CaptureRunTests.Rig(freeBytes: freeBytes)
            self.capture = capture
            self.defaults = defaults
            self.controller = RecordingController(run: capture.run, defaults: defaults)
        }

        static func scratchDefaults() -> UserDefaults {
            UserDefaults(suiteName: "apptape-tests-\(UUID().uuidString)")!
        }
    }

    static let podcast = CaptureRunTests.Rig.source
    static let music = Source(
        bundleID: "com.apple.Music", name: "Music", isPlaying: false, processObjectIDs: [7])
    /// Running, but it has not opened audio, so there is nothing to aim a tap at.
    static let silent = Source(
        bundleID: "com.example.silent", name: "Silent", isPlaying: false, processObjectIDs: [])

    // MARK: - Remembering the Source

    @Test func aFirstLaunchRemembersNoSource() {
        #expect(Rig().controller.source == nil)
    }

    @Test func choosingASourceRemembersItAndStartsNothing() {
        let rig = Rig()
        rig.controller.choose(Self.music)

        #expect(rig.controller.source == SourceChoice(bundleID: "com.apple.Music", name: "Music"))
        #expect(rig.capture.builder.buildCount == 0)
        #expect(rig.capture.run.isRecording == false)
    }

    @Test func theRememberedSourceSurvivesARelaunch() {
        let defaults = Rig.scratchDefaults()
        Rig(defaults: defaults).controller.choose(Self.music)

        let relaunched = Rig(defaults: defaults)
        #expect(relaunched.controller.source == SourceChoice(bundleID: "com.apple.Music", name: "Music"))
    }

    @Test func theSourceIsFixedWhileRecording() {
        let rig = Rig()
        rig.controller.choose(Self.podcast)
        rig.controller.record(among: [Self.podcast, Self.music], from: .window)

        rig.controller.choose(Self.music)

        #expect(rig.controller.source?.bundleID == Self.podcast.bundleID)
        #expect(rig.capture.run.recordingSourceID == Self.podcast.bundleID)
    }

    /// The helper's row is a choice and a press at once, so the window's strip shows what it started.
    @Test func aHelperPressRemembersItsSourceForTheWindow() {
        let rig = Rig()
        rig.controller.choose(Self.music)

        rig.controller.start(Self.podcast, from: .helper)

        #expect(rig.controller.source?.bundleID == Self.podcast.bundleID)
        #expect(rig.capture.run.recordingSourceID == Self.podcast.bundleID)
    }

    // MARK: - Recording the remembered Source

    /// The app quit and relaunched since it was chosen: the same Source, with processes the old choice
    /// never knew.
    @Test func recordingTapsTheRememberedSourceAsItIsRunningNow() {
        let rig = Rig()
        rig.controller.choose(Self.music)
        let relaunched = Source(
            bundleID: "com.apple.Music", name: "Music", isPlaying: true, processObjectIDs: [99])

        rig.controller.record(among: [Self.podcast, relaunched], from: .window)

        #expect(rig.capture.builder.builds.map { $0.source } == [relaunched])
        #expect(rig.capture.run.isRecording)
    }

    @Test func aSourceThatIsNotRunningIsNeverSwappedForAnotherApp() {
        let rig = Rig()
        rig.controller.choose(Self.music)

        // Music has quit, and another app is playing right now.
        rig.controller.record(among: [Self.podcast], from: .window)

        #expect(rig.capture.builder.buildCount == 0)
        #expect(rig.capture.run.isRecording == false)
        #expect(rig.controller.source?.bundleID == Self.music.bundleID)
    }

    @Test func aSourceWithNoAudioYetIsNotRecorded() {
        let rig = Rig()
        rig.controller.choose(Self.silent)

        rig.controller.record(among: [Self.silent], from: .window)

        #expect(rig.capture.builder.buildCount == 0)
        #expect(rig.capture.run.isRecording == false)
    }

    @Test func nothingIsRecordedBeforeASourceIsChosen() {
        let rig = Rig()
        rig.controller.record(among: [Self.podcast], from: .window)
        #expect(rig.capture.builder.buildCount == 0)
    }

    // MARK: - One run, two surfaces

    @Test(arguments: [(CaptureSurface.window, CaptureSurface.helper), (.helper, .window)])
    func aRecordingStartedOnOneSurfaceStopsFromTheOther(started: CaptureSurface, stopped: CaptureSurface) {
        let rig = Rig()
        rig.controller.choose(Self.podcast)
        switch started {
        case .window: rig.controller.record(among: [Self.podcast], from: .window)
        case .helper: rig.controller.start(Self.podcast, from: .helper)
        }
        let capture = rig.capture.builder.finish()
        capture.outcome = CaptureOutcome(result: CaptureRunTests.Rig.result, selfEndReason: nil)

        rig.controller.stop(from: stopped)

        #expect(rig.capture.builder.buildCount == 1)
        #expect(capture.stopCount == 1)
        #expect(rig.capture.run.isRecording == false)
        let url = CaptureRunTests.Rig.result.url
        #expect(rig.capture.reporter.reported == [.authorizationRequested, .saved(url, stoppedFrom: stopped)])
    }

    @Test func aSecondPressWhileRecordingStartsNothing() {
        let rig = Rig()
        rig.controller.choose(Self.podcast)
        rig.controller.record(among: [Self.podcast], from: .window)

        rig.controller.start(Self.music, from: .helper)

        #expect(rig.capture.builder.buildCount == 1)
        #expect(rig.controller.source?.bundleID == Self.podcast.bundleID)
    }

    /// The helper's panel raises itself for a refusal only when the helper pressed; the window's strip
    /// tells its own.
    @Test(arguments: [CaptureSurface.window, .helper])
    func aRefusedPressIsTracedToTheSurfaceThatMadeIt(_ surface: CaptureSurface) {
        let rig = Rig(freeBytes: RunwayGuard.floorBytes - 1)
        rig.controller.choose(Self.podcast)

        switch surface {
        case .window: rig.controller.record(among: [Self.podcast], from: .window)
        case .helper: rig.controller.start(Self.podcast, from: .helper)
        }

        #expect(rig.capture.run.startBlocker != nil)
        #expect(rig.capture.run.isRecording == false)
        #expect(rig.controller.lastPressSurface == surface)
    }

    // MARK: - Readiness

    @Test func readinessFindsTheChosenAppByBundleIDAndNeverAnother() {
        let music = SourceChoice(bundleID: "com.apple.Music", name: "Music")
        let silent = SourceChoice(bundleID: Self.silent.bundleID, name: Self.silent.name)
        let podcast = SourceChoice(bundleID: Self.podcast.bundleID, name: Self.podcast.name)

        #expect(SourceReadiness(choice: nil, among: [Self.podcast]) == .unchosen)
        #expect(SourceReadiness(choice: music, among: [Self.podcast]) == .notRunning(music))
        #expect(SourceReadiness(choice: silent, among: [Self.silent]) == .noAudioYet(Self.silent))
        #expect(SourceReadiness(choice: podcast, among: [Self.music, Self.podcast]) == .ready(Self.podcast))
    }
}
