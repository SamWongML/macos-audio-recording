import AppKit
import UserNotifications

/// Owns the menu bar and handles application lifecycle events.
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

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        EditorPresenter.shared.open()
        return false
    }

    /// Closing the editor leaves the status item and capture running.
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
