//
//  AppDelegate.swift
//  AppTape
//

import AppKit
import UserNotifications

/// The app shell every later ticket hangs on. It owns the hand-rolled menu-bar
/// transport and keeps the process alive when the editor closes, so the app can
/// fall back to a pure `.accessory` menu-bar utility rather than terminating.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let menuBar = MenuBarController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBar.install()
        // A fault notification's click opens the editor on that Recording (ADR-0010).
        UNUserNotificationCenter.current().delegate = FaultNotificationDelegate.shared
        // Sleep, fast user switching, and logout end a Recording on notification, no Seam (ADR-0007).
        RecordingController.shared.installLifecycleObservers()
    }

    /// Closing the editor returns the app to `.accessory` (ADR-0017); it must
    /// not quit — the status item is still the transport.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Quitting navigates away from any running Export, which cancels it unwarned (ADR-0012), and
    /// ends any running Recording as the quit end — finalized and saved, unwarned (ADR-0004/0007).
    /// The destination is untouched until the atomic swap, so a quit mid-encode loses only redoable
    /// work and never a partial file. `endForQuit` finalizes synchronously here, so the CAF and its
    /// Seams are on disk before this returns; the crash-safe CAF (ADR-0003) is the backstop if the
    /// OS kills us before it finishes.
    func applicationWillTerminate(_ notification: Notification) {
        ExportCoordinator.shared.cancel()
        RecordingController.shared.endForQuit()
    }
}
