//
//  AppTapeApp.swift
//  AppTape
//

import SwiftUI

@main
struct AppTapeApp: App {
    /// Owns the hand-rolled `NSStatusItem` transport and the activation-policy
    /// flip — the pieces SwiftUI cannot express (ADR-0004, ADR-0017).
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// Identifies the single editor window so the menu bar can open it.
    static let editorWindowID = "editor"

    var body: some Scene {
        // One editor window, not a WindowGroup: a Recording is edited in place.
        // Suppressed at launch so the app starts as a menu bar item only, and
        // its existence — via `.editorActivationPolicy()` — is what flips the
        // app to `.regular` (ADR-0017).
        Window("AppTape", id: Self.editorWindowID) {
            EditorView()
                .editorActivationPolicy()
        }
        .defaultLaunchBehavior(.suppressed)
        .commands {
            // Trim the standard menu set to what applies (ADR-0017): keep the
            // app's About/Quit, the window's Close ⌘W, the standard Edit items,
            // Window and Help; drop New/Open, Save and Print, which this app has
            // no use for. SidebarCommands/InspectorCommands are deliberately not
            // added (issue #7 found they left the app with zero windows).
            CommandGroup(replacing: .newItem) { }
            CommandGroup(replacing: .saveItem) { }
            CommandGroup(replacing: .printItem) { }
            // No View menu: the spec's set is About/Quit, Close ⌘W, Edit, Window,
            // Help. Pinned here so a later editor toolbar (issue #7) does not
            // silently reintroduce one.
            CommandGroup(replacing: .toolbar) { }
        }
    }
}
