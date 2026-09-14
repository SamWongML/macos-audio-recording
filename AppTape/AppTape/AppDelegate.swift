import AppKit
import UserNotifications

/// The app shell every later ticket hangs on. It owns the hand-rolled menu-bar
/// transport and keeps the process alive when the editor closes, so the app can
/// fall back to a pure `.accessory` menu-bar utility rather than terminating.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// **The other of the two places an app singleton is named**; `AppTapeApp` is the
    /// SwiftUI one. The status item and the panel it hosts are handed the transport rather than
    /// reaching for it.
    let menuBar = MenuBarController(recorder: .shared, presenter: .shared)

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBar.install()
        // A fault notification's click opens the editor on that Recording.
        UNUserNotificationCenter.current().delegate = FaultNotificationDelegate.shared
        // Sleep, fast user switching, and logout end a Recording on notification, no Dropout.
        RecordingController.shared.installLifecycleObservers()
    }

    /// Closing the editor returns the app to `.accessory`; it must
    /// not quit — the status item is still the transport.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Quitting navigates away from any running Export, which cancels it unwarned, and
    /// ends any running Recording as the quit end — finalized and saved, unwarned (/0007).
    /// The destination is untouched until the atomic swap, so a quit mid-encode loses only redoable
    /// work and never a partial file. `endForQuit` finalizes synchronously here, so the CAF and its
    /// Dropouts are on disk before this returns; the crash-safe CAF is the backstop if the
    /// OS kills us before it finishes.
    func applicationWillTerminate(_ notification: Notification) {
        ExportCoordinator.shared.cancel()
        RecordingController.shared.endForQuit()
    }
}
