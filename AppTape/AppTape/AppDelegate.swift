import AppKit
import UserNotifications

/// The AppKit shell: owns the menu bar and the activation policy.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
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

    /// Quitting navigates away from any running Export, which cancels it unwarned, and ends any
    /// running Recording as the quit end — finalized and saved, unwarned (/0007).
    func applicationWillTerminate(_ notification: Notification) {
        ExportCoordinator.shared.cancel()
        RecordingController.shared.endForQuit()
    }
}
