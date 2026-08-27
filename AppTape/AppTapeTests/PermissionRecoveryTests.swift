//
//  PermissionRecoveryTests.swift
//  AppTapeTests
//

import Testing
@testable import AppTape

/// The recovery surface's two load-bearing facts (ADR-0008): the deep link is exactly the one
/// verified to open the audio-capture pane, and the copy names "System Audio Recording Only"
/// rather than the pane's own broader heading.
struct PermissionRecoveryTests {
    @Test func deepLinkIsTheVerifiedAudioCapturePane() {
        #expect(PermissionRecovery.settingsURLString
            == "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")
        // It must parse as a URL, or `NSWorkspace.open` silently does nothing.
        #expect(PermissionRecovery.settingsURL != nil)
    }

    @Test func copyNamesSystemAudioRecordingOnly() {
        #expect(PermissionRecovery.message.contains("System Audio Recording Only"))
    }

    @Test func copyEndsOnPressRecordAgain() {
        #expect(PermissionRecovery.message.contains("press record again"))
    }
}
