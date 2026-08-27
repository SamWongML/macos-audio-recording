//
//  PermissionRecovery.swift
//  AppTape
//

import Foundation

/// The copy and the deep link the panel shows when a denied *System Audio Recording* grant is
/// inferred (ADR-0008). Kept as plain constants so the exact link and the load-bearing wording
/// are pinned by a test rather than buried in a view.
enum PermissionRecovery {
    /// The System Settings deep link that lands on the audio-capture privacy pane. Verified to
    /// work on macOS 27 — but it opens a window titled **"Screen & System Audio Recording"**,
    /// with the audio-only section inside it. An app that promises it never wants screen access
    /// must name **"System Audio Recording Only"** in its own copy, so the pane's heading does
    /// not read as a contradiction (ADR-0008).
    static let settingsURLString = "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture"

    static var settingsURL: URL? { URL(string: settingsURLString) }

    static let title = "Couldn’t record this app’s audio"

    /// Names "System Audio Recording Only" (not the pane's own broader heading) and ends on the
    /// retry, which is simply pressing record again — a fresh tap in the same process recovers
    /// within about a second once the grant lands (ADR-0008).
    static let message = "macOS hasn’t granted permission. In System Settings, turn on "
        + "“System Audio Recording Only” for AppTape, then press record again."
}
