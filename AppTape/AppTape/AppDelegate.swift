//
//  AppDelegate.swift
//  AppTape
//

import AppKit

/// The app shell every later ticket hangs on. It owns the hand-rolled menu-bar
/// transport and keeps the process alive when the editor closes, so the app can
/// fall back to a pure `.accessory` menu-bar utility rather than terminating.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let menuBar = MenuBarController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBar.install()
    }

    /// Closing the editor returns the app to `.accessory` (ADR-0017); it must
    /// not quit — the status item is still the transport.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Quitting navigates away from any running Export, which cancels it unwarned (ADR-0012).
    /// The destination is untouched until the atomic swap, so a quit mid-encode loses only
    /// redoable work and never a partial file.
    func applicationWillTerminate(_ notification: Notification) {
        ExportCoordinator.shared.cancel()
    }
}
