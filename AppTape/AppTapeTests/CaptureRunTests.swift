//
//  CaptureRunTests.swift
//  AppTapeTests
//

import Foundation
import Testing
@testable import AppTape

/// One press's whole life, with Core Audio, a `statfs`, a notification centre and a window replaced
/// by doubles, and with time handed in rather than waited for.
///
/// The three things that were untestable before the seam and are the reason for it: ADR-0010's
/// **generation rule** — a slow or cancelled bring-up must not attach to a later press, which used
/// to be one line hand-copied to eight sites; the **wedge**, armed only after the first successful
/// capture so a ~90 s TCC prompt is never mistaken for a hang (ADR-0008); and **six ends**, each
/// telling the user a different thing (ADR-0007/0009).
@MainActor
struct CaptureRunTests {

    // MARK: - Fixtures

    /// The run under test with its three doubles, wired together. Explicitly `@MainActor`: a
    /// nested type does not inherit its enclosing type's isolation, and this test target does not
    /// carry the app's `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
    @MainActor
    struct Rig {
        let builder: FakeCaptureBuilder
        let runway: StubRunway
        let telling: TellingLog
        let run: CaptureRun

        /// ~500 GB free: far past the 3-hour amber tier at any sample rate.
        init(freeBytes: Int64? = 500_000_000_000) {
            let builder = FakeCaptureBuilder()
            let runway = StubRunway(freeBytes: freeBytes)
            let telling = TellingLog()
            self.builder = builder
            self.runway = runway
            self.telling = telling
            self.run = CaptureRun(builder: builder, runway: runway, telling: telling)
        }

        /// Press record and let the bring-up succeed — where every test that is not about bring-up
        /// itself starts.
        @discardableResult
        func startCapturing(now: TimeInterval = 0) -> FakeCapture {
            run.start(Self.source, now: now)
            return builder.finish()
        }

        /// Capture one complete Recording, which is what arms the wedge for the next press.
        func completeARecording() {
            let capture = startCapturing()
            capture.outcome = CaptureOutcome(result: Self.result, selfEndReason: nil)
            run.stop()
        }

        static let source = Source(bundleID: "com.example.podcast", name: "Podcast",
                                   isPlaying: true, processObjectIDs: [42])
        static let result = CaptureResult(url: URL(filePath: "/tmp/apptape-test.caf"),
                                          frameCount: 48_000, sampleRate: 48_000)
    }

    /// 48 kHz stereo Float32 → 8 bytes/frame, ADR-0009's worked rate.
    static let rate: Double = 8 * 48_000
    /// Free bytes that put Runway exactly `seconds` from the floor.
    static func freeBytes(runway seconds: TimeInterval) -> Int64 {
        RunwayGuard.floorBytes + Int64(seconds * rate)
    }
    /// One 20 Hz tick, the cadence `RecordingController` drives the run at.
    static func tick(_ index: Int) -> TimeInterval { Double(index) / 20 }

    // MARK: - The generation rule (ADR-0010)

    @Test func aSecondPressDuringBringUpOrphansTheFirstAttemptsCapture() {
        let rig = Rig()
        rig.run.start(Rig.source, now: 0)
        #expect(rig.run.isRecording)
        #expect(rig.builder.isBuilding())

        // The second click is the cancel gesture: the UI returns to idle at once, because the
        // blocked Core Audio call cannot be interrupted (ADR-0010).
        rig.run.stop()
        #expect(rig.run.isRecording == false)

        // The blocked call finally returns. It must be torn down, not attached.
        let orphan = rig.builder.finish()
        #expect(orphan.stopCount == 1)
        #expect(rig.run.isRecording == false)
        #expect(rig.run.capturingURL == nil)
    }

    @Test func aLateCaptureDoesNotAttachToALaterPress() {
        let rig = Rig()
        rig.run.start(Rig.source, now: 0)   // attempt 1, blocked
        rig.run.stop()                      // cancelled
        rig.run.start(Rig.source, now: 1)   // attempt 2, its own bring-up
        let live = rig.builder.finish(build: 1)
        #expect(rig.run.isRecording)

        // Attempt 1's call returns into a world that has moved on.
        let orphan = rig.builder.finish(build: 0)
        #expect(orphan.stopCount == 1)
        #expect(live.stopCount == 0)
        #expect(rig.run.isRecording)
    }

    @Test func aDenialBeforeTheCaptureArrivesStillRaisesRecovery() {
        let rig = Rig()
        rig.run.start(Rig.source, now: 0)
        // The writer thread infers denial while the main actor has not yet picked up the bring-up —
        // the gap ADR-0008's 3 s window leaves open. Nothing here may depend on `attach` having run.
        rig.builder.hooks(forBuild: 0).onDenialInferred()

        #expect(rig.run.permissionRecovery)
        #expect(rig.run.isRecording == false)
        #expect(rig.run.startRefusal == nil)   // the panel carries one blocking reason (ADR-0009)

        // And the capture that arrives afterwards is orphaned rather than left running.
        let orphan = rig.builder.finish()
        #expect(orphan.stopCount == 1)
        #expect(rig.run.permissionRecovery)
    }

    @Test func aDenialFromAnAbandonedAttemptChangesNothing() {
        let rig = Rig()
        rig.run.start(Rig.source, now: 0)
        rig.run.stop()
        rig.builder.hooks(forBuild: 0).onDenialInferred()
        #expect(rig.run.permissionRecovery == false)
        #expect(rig.run.isRecording == false)
    }

    @Test func aMasterCreatedByAnAbandonedAttemptIsNotTheCapturingURL() {
        let rig = Rig()
        rig.startCapturing()
        rig.run.stop()
        rig.run.start(Rig.source, now: 1)
        rig.builder.finish(build: 1)

        // Attempt 1's writer thread reports its first sound after the fact.
        rig.builder.hooks(forBuild: 0).onMasterCreated(URL(filePath: "/tmp/stale.caf"))
        #expect(rig.run.capturingURL == nil)
        #expect(rig.run.hasFirstSound == false)
    }

    @Test func aSelfEndFromAnAbandonedAttemptDoesNotFinalizeTheLiveOne() {
        let rig = Rig()
        let first = rig.startCapturing()
        rig.run.stop()
        #expect(first.stopCount == 1)

        rig.run.start(Rig.source, now: 1)
        let second = rig.builder.finish(build: 1)
        rig.builder.hooks(forBuild: 0).onEnded(.recoveryExhausted)

        #expect(rig.run.isRecording)
        #expect(second.stopCount == 0)
        #expect(first.stopCount == 1)   // not finalized twice
    }

    // MARK: - The wedge (ADR-0008/0010)

    @Test func theFirstBringUpIsCancellableNotTimed() {
        let rig = Rig()
        rig.run.start(Rig.source, now: 0)
        // ADR-0008 measured 60 + 30 s of legitimate blocking while a human reads the TCC prompt, and
        // the human is the variable — so no number may end this attempt.
        for i in 1...(90 * 20) { rig.run.tick(now: Self.tick(i)) }
        #expect(rig.run.isRecording)
        #expect(rig.builder.isBuilding())
    }

    @Test func aSlowBringUpAfterASuccessIsAWedgeAndTimesOut() {
        let rig = Rig()
        rig.completeARecording()
        #expect(rig.run.hasCompletedACapture)

        rig.run.start(Rig.source, now: 100)
        rig.run.tick(now: 100 + CaptureRun.wedgeTimeout - 0.05)
        #expect(rig.run.isRecording)
        rig.run.tick(now: 100 + CaptureRun.wedgeTimeout)
        #expect(rig.run.isRecording == false)
    }

    @Test func aCaptureArrivingBeforeTheWedgeDisarmsIt() {
        let rig = Rig()
        rig.completeARecording()

        rig.run.start(Rig.source, now: 100)
        rig.run.tick(now: 109.9)
        rig.builder.finish(build: 1)        // attached with 0.1 s to spare
        for i in 0...(50 * 20) { rig.run.tick(now: 110 + Self.tick(i)) }
        #expect(rig.run.isRecording)
    }

    @Test func aBringUpThatThrowsReturnsToIdle() {
        let rig = Rig()
        rig.run.start(Rig.source, now: 0)
        rig.builder.fail()
        #expect(rig.run.isRecording == false)
        #expect(rig.run.permissionRecovery == false)
        #expect(rig.run.startRefusal == nil)
    }

    // MARK: - The six ends (ADR-0007/0010)

    @Test func aUserStopRequestsAuthorizationOnceAndOpensTheEditor() {
        let rig = Rig()
        let capture = rig.startCapturing()
        capture.outcome = CaptureOutcome(result: Rig.result, selfEndReason: nil)
        rig.run.stop()

        #expect(rig.telling.told == [.authorizationRequested, .editorOpened(Rig.result.url)])
        #expect(rig.run.hasCompletedACapture)
        #expect(rig.run.isRecording == false)
    }

    @Test func quitFinalizesSynchronouslyAndTellsNothing() {
        let rig = Rig()
        let capture = rig.startCapturing()
        capture.outcome = CaptureOutcome(result: Rig.result, selfEndReason: nil)
        rig.run.endForQuit()

        // The process is about to exit: the CAF must close and the Seams xattr must be written
        // before `applicationWillTerminate` returns, so this is the one end that does not offload.
        #expect(capture.stopNowCount == 1)
        #expect(capture.stopCount == 0)
        #expect(rig.telling.told.isEmpty)
        #expect(rig.run.isRecording == false)
    }

    @Test(arguments: [RecordingEndReason.diskGuard, .recoveryExhausted, .formatMismatch, .sleep])
    func anUnrequestedEndNamesItsReasonAndOpensNoWindow(_ reason: RecordingEndReason) {
        let rig = Rig()
        let capture = rig.startCapturing()
        capture.outcome = CaptureOutcome(result: Rig.result, selfEndReason: reason)
        rig.builder.hooks(forBuild: 0).onEnded(reason)

        // The reason is named because the four ask different things of the user, and a generic
        // "Recording stopped" makes them open the app to find out which (ADR-0010).
        #expect(rig.telling.told == [.end(reason, Rig.result.url)])
        #expect(rig.run.isRecording == false)
    }

    @Test func theCapturesOwnReasonWinsOverTheCallers() {
        let rig = Rig()
        let capture = rig.startCapturing()
        // The capture already ended itself at the disk floor; the sleep notification lands after.
        capture.outcome = CaptureOutcome(result: Rig.result, selfEndReason: .diskGuard)
        rig.run.end(.sleep)
        #expect(rig.telling.told == [.end(.diskGuard, Rig.result.url)])
    }

    @Test func armThenNeverPlaySavesNothingAndTellsNothing() {
        let rig = Rig()
        let capture = rig.startCapturing()   // the default outcome carries no file (ADR-0016)
        rig.run.stop()

        #expect(capture.stopCount == 1)
        #expect(rig.telling.told.isEmpty)
        // No capture means nothing is known about the grant, so the wedge stays disarmed.
        #expect(rig.run.hasCompletedACapture == false)
    }

    @Test func aFaultEndedRecordingStillArmsTheWedge() {
        let rig = Rig()
        let capture = rig.startCapturing()
        capture.outcome = CaptureOutcome(result: Rig.result, selfEndReason: .recoveryExhausted)
        rig.builder.hooks(forBuild: 0).onEnded(.recoveryExhausted)

        // It captured audio, so the grant is known good and a later slow bring-up is a hang.
        #expect(rig.run.hasCompletedACapture)
    }

    // MARK: - The Runway guard, composed (ADR-0009)

    @Test func aPressBelowTheFloorIsRefusedAndStartsNoBringUp() {
        let rig = Rig(freeBytes: RunwayGuard.floorBytes - 1)
        rig.run.start(Rig.source, now: 0)

        #expect(rig.run.isRecording == false)
        #expect(rig.run.startRefusal != nil)
        #expect(rig.run.permissionRecovery == false)
        #expect(rig.builder.buildCount == 0)   // no tap is even asked for
    }

    @Test func aPressInsideTheAmberTierBeginsAmber() {
        // One hour of Runway: above the floor, inside the 3-hour tier. Beginning nominal here would
        // flash green for the seconds before the first real poll (ADR-0009).
        let rig = Rig(freeBytes: Self.freeBytes(runway: 60 * 60))
        rig.run.start(Rig.source, now: 0)
        #expect(rig.run.runwayTier == .amber)
    }

    @Test func theGuardPollsEveryFiveSecondsAndNotEveryTick() {
        let rig = Rig()
        rig.startCapturing()
        let atStart = rig.runway.pollCount   // the start decision's own read

        // Five seconds of 20 Hz ticks: the first one polls, the other ninety-nine do not.
        for i in 1...100 { rig.run.tick(now: Self.tick(i)) }
        #expect(rig.runway.pollCount == atStart + 1)

        rig.run.tick(now: 5.05)
        #expect(rig.runway.pollCount == atStart + 2)
    }

    @Test func crossingThirtyMinutesWarnsExactlyOnce() {
        let rig = Rig()
        let capture = rig.startCapturing()
        capture.bytesPerSecond = Self.rate
        rig.run.tick(now: 0.05)              // the first poll, well above the band

        rig.runway.freeBytes = Self.freeBytes(runway: 20 * 60)
        var now = 5.05
        for _ in 0..<10 {
            rig.run.tick(now: now)
            now += 5
        }

        // A posted warning is never retracted and never doubled: the 15-minute hysteresis holds it
        // to one for as long as the Recording stays in the band.
        #expect(rig.telling.told.filter { $0 == .runwayLow }.count == 1)
        #expect(rig.run.isRecording)         // a warning is not an end
    }

    @Test func reachingTheFloorEndsTheRecordingAsDiskGuard() {
        let rig = Rig()
        let capture = rig.startCapturing()
        capture.outcome = CaptureOutcome(result: Rig.result, selfEndReason: nil)
        rig.run.tick(now: 0.05)

        rig.runway.freeBytes = RunwayGuard.floorBytes - 1
        rig.run.tick(now: 5.05)

        #expect(rig.run.isRecording == false)
        #expect(rig.telling.told == [.end(.diskGuard, Rig.result.url)])
    }

    @Test func anUnverifiableVolumeNeitherRefusesAPressNorEndsARecording() {
        let rig = Rig(freeBytes: nil)
        rig.run.start(Rig.source, now: 0)
        #expect(rig.run.isRecording)
        #expect(rig.run.startRefusal == nil)
        #expect(rig.run.runwayTier == .nominal)   // not pre-ambered either

        rig.builder.finish()
        for i in 1...(30 * 20) { rig.run.tick(now: Self.tick(i)) }
        #expect(rig.run.isRecording)
        #expect(rig.telling.told.isEmpty)
    }

    // MARK: - Cadence and the meter

    @Test func theClockPublishesAtFourHertzEvenWhenTickedAtTwenty() {
        let rig = Rig()
        let capture = rig.startCapturing()

        capture.elapsed = 1
        rig.run.tick(now: 0.05)
        #expect(rig.run.elapsed == 1)

        // The menu bar observes `elapsed`, so publishing it at the meter's cadence would quintuple
        // status-item churn for nothing anyone can read.
        capture.elapsed = 2
        rig.run.tick(now: 0.10)
        rig.run.tick(now: 0.15)
        rig.run.tick(now: 0.25)
        #expect(rig.run.elapsed == 1)

        rig.run.tick(now: 0.30)
        #expect(rig.run.elapsed == 2)
    }

    @Test func theClockReadsMinutesAndThenHours() {
        let rig = Rig()
        let capture = rig.startCapturing()
        #expect(rig.run.elapsedText == "00:00")

        capture.elapsed = 83
        rig.run.tick(now: 0.05)
        #expect(rig.run.elapsedText == "01:23")

        capture.elapsed = 3723
        rig.run.tick(now: 0.35)
        #expect(rig.run.elapsedText == "1:02:03")
    }

    @Test func elapsedSitsAtZeroThroughTheArmedWindow() {
        let rig = Rig()
        rig.startCapturing()   // armed, but the Source has made no sound yet (ADR-0016)

        for i in 1...100 { rig.run.tick(now: Self.tick(i)) }
        #expect(rig.run.elapsed == 0)
        #expect(rig.run.elapsedText == "00:00")
        #expect(rig.run.hasFirstSound == false)
    }

    @Test func aNewRecordingInheritsNoMeterTail() {
        let rig = Rig()
        let capture = rig.startCapturing()
        capture.currentLevel = 1
        for i in 1...(CaptureRun.meterColumnCount + 10) { rig.run.tick(now: Self.tick(i)) }
        #expect(rig.run.currentLevel > 0)
        #expect(rig.run.meterColumns.allSatisfy { $0 > 0 })

        rig.run.stop()
        #expect(rig.run.currentLevel == 0)
        #expect(rig.run.meterColumns.allSatisfy { $0 == 0 })

        rig.run.start(Rig.source, now: 10)
        #expect(rig.run.meterColumns.allSatisfy { $0 == 0 })
    }

    @Test func aDeadTapFlattensTheMeterRatherThanFreezingIt() {
        let rig = Rig()
        let capture = rig.startCapturing()
        capture.currentLevel = 1
        for i in 1...(CaptureRun.meterColumnCount + 10) { rig.run.tick(now: Self.tick(i)) }
        #expect(rig.run.currentLevel > 0)

        // A soft fault publishes an all-zero chunk: exactly 0, never a stale ghost (issue #59).
        capture.currentLevel = 0
        let resumeAt = CaptureRun.meterColumnCount + 11
        for i in resumeAt...(resumeAt + CaptureRun.meterColumnCount) { rig.run.tick(now: Self.tick(i)) }
        #expect(rig.run.currentLevel == 0)
        #expect(rig.run.meterColumns.allSatisfy { $0 == 0 })
    }

    // MARK: - The growing master

    @Test func theGrowingMasterIsCapturingAndStillArriving() throws {
        let directory = try AudioFixtures.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let growing = try AudioFixtures.writeCAF(at: directory.appendingPathComponent("growing.caf"))
        let settled = try AudioFixtures.writeCAF(at: directory.appendingPathComponent("settled.caf"))
        let growingRecording = try #require(Recording(url: growing))
        let settledRecording = try #require(Recording(url: settled))

        let rig = Rig()
        rig.startCapturing()
        rig.builder.hooks(forBuild: 0).onMasterCreated(growing)

        // The one being written is not exportable: its Trim end is undefined until Stop (ADR-0012).
        #expect(rig.run.isCapturing(growingRecording))
        #expect(rig.run.isStillArriving(growingRecording))
        #expect(rig.run.isCapturing(settledRecording) == false)
        #expect(rig.run.isStillArriving(settledRecording) == false)

        rig.run.stop()
        #expect(rig.run.isCapturing(growingRecording) == false)
        #expect(rig.run.isStillArriving(growingRecording) == false)
    }
}
