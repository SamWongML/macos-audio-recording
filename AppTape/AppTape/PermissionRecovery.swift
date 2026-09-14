import Foundation

/// The copy and the deep link the panel shows when a denied *System Audio Recording* grant is
/// inferred.
enum PermissionRecovery {
    /// The System Settings deep link that lands on the audio-capture privacy pane.
    static let settingsURLString = "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture"

    static var settingsURL: URL? { URL(string: settingsURLString) }

    static let title = "Couldn’t record this app’s audio"

    /// Names "System Audio Recording Only" (not the pane's own broader heading) and ends on the
    /// retry, which is simply pressing record again — a fresh tap in the same process recovers
    /// within about a second once the grant lands.
    static let message = "macOS hasn’t granted permission. In System Settings, turn on "
        + "“System Audio Recording Only” for AppTape, then press record again."
}
