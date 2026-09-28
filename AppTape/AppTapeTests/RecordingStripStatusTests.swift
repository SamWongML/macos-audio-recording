import Foundation
import Testing

@testable import AppTape

/// What the recording strip says, read off a run driven through `CaptureRunTests`' doubles.
@MainActor
struct RecordingStripStatusTests {
    typealias Rig = CaptureRunTests.Rig

    static let ready = SourceReadiness.ready(Rig.source)
    static let firstSound = URL(filePath: "/Library/Podcast 2026-09-28 at 10.41.07.caf")

    @Test func aPressWaitsForTheFirstSoundAndOnlyThenRecords() {
        let rig = Rig()
        #expect(RecordingStripStatus(run: rig.run, readiness: Self.ready) == .ready(Rig.source))

        rig.run.start(Rig.source, now: 0)
        #expect(RecordingStripStatus(run: rig.run, readiness: Self.ready) == .waitingForAudio)

        // Brought up and armed, and still silent: the master has not begun, so neither has the clock.
        rig.builder.finish()
        #expect(RecordingStripStatus(run: rig.run, readiness: Self.ready) == .waitingForAudio)

        rig.builder.hooks().onMasterCreated(Self.firstSound)
        #expect(RecordingStripStatus(run: rig.run, readiness: Self.ready) == .recording(lowRunway: false))
    }

    @Test func aRecordingInsideTheAmberTierSaysSo() {
        let rig = Rig(freeBytes: CaptureRunTests.freeBytes(runway: 60 * 60))
        rig.startCapturing()
        rig.builder.hooks().onMasterCreated(Self.firstSound)

        let status = RecordingStripStatus(run: rig.run, readiness: Self.ready)
        #expect(status == .recording(lowRunway: true))
        #expect(status.announcement == "Recording. Disk space running low")
    }

    @Test func captureOutranksTheSourceAfterItStarted() {
        let rig = Rig()
        rig.startCapturing()
        let quit = SourceChoice(bundleID: Rig.source.bundleID, name: Rig.source.name)

        // The Source quit mid-Recording: capture carries on, and the strip keeps saying so.
        #expect(RecordingStripStatus(run: rig.run, readiness: .notRunning(quit)) == .waitingForAudio)
    }

    @Test func aRefusalIsTheStripsToTellAndRecordRetriesIt() throws {
        let rig = Rig(freeBytes: RunwayGuard.floorBytes - 1)
        rig.run.start(Rig.source, now: 0)
        let blocker = try #require(rig.run.startBlocker)

        let status = RecordingStripStatus(run: rig.run, readiness: Self.ready)
        #expect(status == .refusedForSpace(blocker))
        #expect(status.canRecord)
    }

    @Test func aDenialIsTheStripsToTellAndRecordRetriesIt() {
        let rig = Rig()
        rig.run.start(Rig.source, now: 0)
        rig.builder.hooks().onDenialInferred()

        let status = RecordingStripStatus(run: rig.run, readiness: Self.ready)
        #expect(status == .permissionDenied)
        #expect(status.canRecord)
    }

    /// A refusal is left standing until the next press, but it does not explain a Record that is
    /// disabled for another reason.
    @Test func whyTheSourceCannotBeRecordedOutranksAStaleRefusal() {
        let rig = Rig(freeBytes: RunwayGuard.floorBytes - 1)
        rig.run.start(Rig.source, now: 0)
        let music = SourceChoice(bundleID: "com.apple.Music", name: "Music")

        let status = RecordingStripStatus(run: rig.run, readiness: .notRunning(music))
        #expect(status == .notRunning(music))
        #expect(status.canRecord == false)
    }

    @Test func recordIsOfferedOnlyWithARecordableSource() {
        let rig = Rig()
        let silent = Source(
            bundleID: "com.example.silent", name: "Silent", isPlaying: false, processObjectIDs: [])

        #expect(RecordingStripStatus(run: rig.run, readiness: .unchosen).canRecord == false)
        #expect(RecordingStripStatus(run: rig.run, readiness: .noAudioYet(silent)).canRecord == false)
        #expect(RecordingStripStatus(run: rig.run, readiness: Self.ready).canRecord)

        rig.startCapturing()
        #expect(RecordingStripStatus(run: rig.run, readiness: Self.ready).canRecord == false)
    }

    @Test func onlyStateChangesAreAnnouncedNotTheClock() {
        let rig = Rig()
        let capture = rig.startCapturing()
        rig.builder.hooks().onMasterCreated(Self.firstSound)
        let before = RecordingStripStatus(run: rig.run, readiness: Self.ready)

        capture.elapsed = 83
        rig.run.tick(now: 0.05)
        let after = RecordingStripStatus(run: rig.run, readiness: Self.ready)

        #expect(before == after)
        #expect(after.announcement == "Recording")
    }
}
