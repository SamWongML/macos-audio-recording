//
//  RecordingEndReasonTests.swift
//  AppTapeTests
//

import Testing
@testable import AppTape

/// A Recording ends for exactly six reasons; four are unrequested and notify with a named reason,
/// two are requested and stay silent (ADR-0007, ADR-0010).
struct RecordingEndReasonTests {
    @Test func thereAreExactlySixEnds() {
        #expect(RecordingEndReason.allCases.count == 6)
    }

    @Test func exactlyFourEndsAreUnrequested() {
        let unrequested = RecordingEndReason.allCases.filter(\.isUnrequested)
        #expect(Set(unrequested) == [.diskGuard, .recoveryExhausted, .formatMismatch, .sleep])
    }

    @Test func theTwoRequestedEndsStaySilent() {
        #expect(RecordingEndReason.userStopped.isUnrequested == false)
        #expect(RecordingEndReason.quit.isUnrequested == false)
        #expect(RecordingEndReason.userStopped.notificationBody == nil)
        #expect(RecordingEndReason.quit.notificationBody == nil)
    }

    @Test func everyUnrequestedEndNamesItsReasonInTheBody() {
        for reason in RecordingEndReason.allCases where reason.isUnrequested {
            let body = reason.notificationBody
            #expect(body != nil)
            #expect(body?.isEmpty == false)
        }
    }

    @Test func theTitleStaysCalmAndConstant() {
        for reason in RecordingEndReason.allCases where reason.isUnrequested {
            #expect(reason.notificationTitle == "Recording stopped")
        }
    }
}
