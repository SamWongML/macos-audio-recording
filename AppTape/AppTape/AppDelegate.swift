import AppKit
import UserNotifications

/// The AppKit shell: owns the menu bar and the activation policy.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let menuBar = MenuBarController(recorder: .shared, presenter: .shared)
    private var menuBarOwnerObservation: NSKeyValueObservation?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarOwnerObservation = NSWorkspace.shared.observe(\.menuBarOwningApplication) { _, _ in
            DispatchQueue.main.async {
                ActivationPolicyController.shared.applicationStateDidChange()
            }
        }
        menuBar.install()
        // A fault notification's click opens the editor on that Recording.
        UNUserNotificationCenter.current().delegate = FaultNotificationDelegate.shared
        // Sleep, fast user switching, and logout end a Recording on notification, no Dropout.
        RecordingController.shared.installLifecycleObservers()
    }

    func applicationDidResignActive(_ notification: Notification) {
        ActivationPolicyController.shared.applicationStateDidChange()
    }

    func applicationDidHide(_ notification: Notification) {
        ActivationPolicyController.shared.applicationStateDidChange()
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
